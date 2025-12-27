import AsyncAlgorithms
import AsyncQueue
import Clocks
import Foundation
import HTTPTypes
import HTTPTypesFoundation

struct WebSocketReconnectionConfig {
    let enabled: Bool
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double

    static let `default` = Self(
        enabled: true,
        initialDelay: 2.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0,
    )

    static let disabled = Self(
        enabled: false,
        initialDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0,
    )
}

enum WebSocketStreamEvent {
    case connected(headers: HTTPFields?)
    case disconnected(reason: String?, code: UInt16)
    case text(String)
    case data(Data)
    case error(Error)
}

protocol WebSocketStreamClient: AnyObject {
    var events: AsyncChannel<WebSocketStreamEvent> { get }

    func connect()
    func disconnect(closeCode: UInt16?)

    func send(text: String)
    func send(data: Data)
}

final class URLSessionWebSocketStreamClient: NSObject, WebSocketStreamClient, @unchecked Sendable {
    private let request: URLRequest
    private let reconnectionConfig: WebSocketReconnectionConfig
    private let clock: any Clock<Duration>
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let channel = AsyncChannel<WebSocketStreamEvent>()
    private let queue = FIFOQueue(name: "WebSocketStreamClient")

    private var _isManuallyDisconnected = false
    private var _reconnectTask: Task<Void, Never>?
    private var _reconnectAttempt = 0
    private var _currentDelay: TimeInterval

    private var isManuallyDisconnected: Bool {
        get { _isManuallyDisconnected }
        set { _isManuallyDisconnected = newValue }
    }

    private var reconnectTask: Task<Void, Never>? {
        get { _reconnectTask }
        set { _reconnectTask = newValue }
    }

    private var currentDelay: TimeInterval {
        get { _currentDelay }
        set { _currentDelay = newValue }
    }

    init(
        request: URLRequest,
        reconnectionConfig: WebSocketReconnectionConfig = .default,
        clock: any Clock<Duration> = ContinuousClock(),
    ) {
        self.request = request
        self.reconnectionConfig = reconnectionConfig
        self.clock = clock
        self._currentDelay = reconnectionConfig.initialDelay
        super.init()
    }

    private func setupWebSocket() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.urlSession = session
        self.webSocketTask = task
    }

    var events: AsyncChannel<WebSocketStreamEvent> {
        channel
    }

    func connect() {
        Task(on: queue) {
            _isManuallyDisconnected = false
            _reconnectAttempt = 0
            _currentDelay = reconnectionConfig.initialDelay
        }
        reconnectTask?.cancel()
        Task(on: queue) {
            _reconnectTask = nil
        }

        setupWebSocket()
        webSocketTask?.resume()
        startReceiving()
    }

    func disconnect(closeCode: UInt16? = nil) {
        Task(on: queue) {
            _isManuallyDisconnected = true
        }
        reconnectTask?.cancel()
        Task(on: queue) {
            _reconnectTask = nil
        }

        let closeCode = closeCode.map { URLSessionWebSocketTask.CloseCode(rawValue: Int($0)) ?? .normalClosure } ?? .normalClosure
        webSocketTask?.cancel(with: closeCode, reason: nil)
        channel.finish()
    }

    func send(text: String) {
        Task(on: queue) {
            webSocketTask?.send(.string(text)) { [weak self] error in
                if let error {
                    Task {
                        await self?.channel.send(.error(error))
                    }
                }
            }
        }
    }

    func send(data: Data) {
        Task(on: queue) {
            webSocketTask?.send(.data(data)) { [weak self] error in
                if let error {
                    Task {
                        await self?.channel.send(.error(error))
                    }
                }
            }
        }
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            Task {
                switch result {
                case let .success(message):
                    switch message {
                    case let .string(text):
                        await self.channel.send(.text(text))
                    case let .data(data):
                        await self.channel.send(.data(data))
                    @unknown default:
                        break
                    }
                    self.startReceiving()

                case let .failure(error):
                    await self.channel.send(.error(error))
                    if !self.isManuallyDisconnected {
                        self.scheduleReconnect()
                    } else {
                        channel.finish()
                    }
                }
            }
        }
    }

    private func scheduleReconnect() {
        let shouldReconnect = reconnectionConfig.enabled && !_isManuallyDisconnected

        guard shouldReconnect else {
            Task {
                channel.finish()
            }
            return
        }

        reconnectTask?.cancel()

        let delay = currentDelay
        let backoffMultiplier = reconnectionConfig.backoffMultiplier
        let maxDelay = reconnectionConfig.maxDelay

        let task = Task.detached { [weak self] in
            guard let self else { return }

            try? await clock.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                return
            }

            let stillShouldReconnect = !_isManuallyDisconnected

            guard stillShouldReconnect else {
                return
            }

            _reconnectAttempt += 1
            _currentDelay = min(
                _currentDelay * backoffMultiplier,
                maxDelay,
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.setupWebSocket()
                self.webSocketTask?.resume()
                self.startReceiving()
            }
        }

        _reconnectTask = task
    }
}

extension URLSessionWebSocketStreamClient: URLSessionWebSocketDelegate {
    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        let headers: HTTPFields? = nil
        Task {
            await channel.send(.connected(headers: headers))
        }

        _reconnectAttempt = 0
        _currentDelay = reconnectionConfig.initialDelay
        reconnectTask?.cancel()
        _reconnectTask = nil
    }

    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        Task {
            await channel.send(.disconnected(reason: reasonString, code: UInt16(closeCode.rawValue)))
            if !self.isManuallyDisconnected {
                self.scheduleReconnect()
            } else {
                channel.finish()
            }
        }
    }
}

struct TrafficDataStream: AsyncSequence {
    typealias Element = TrafficSnapshot

    let events: AsyncChannel<WebSocketStreamEvent>

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(events: events)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var eventIterator: AsyncChannel<WebSocketStreamEvent>.AsyncIterator

        init(events: AsyncChannel<WebSocketStreamEvent>) {
            self.eventIterator = events.makeAsyncIterator()
        }

        mutating func next() async throws -> TrafficSnapshot? {
            while let event = await eventIterator.next() {
                switch event {
                case let .text(text):
                    guard let data = text.data(using: .utf8),
                          let traffic = try? JSONDecoder().decode(TrafficSnapshot.self, from: data)
                    else {
                        continue
                    }
                    return traffic
                case let .error(error):
                    throw error
                case .disconnected:
                    return nil
                default:
                    continue
                }
            }
            return nil
        }
    }
}

struct WebSocketMessageStream: AsyncSequence {
    typealias Element = String

    let events: AsyncChannel<WebSocketStreamEvent>

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(events: events)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var eventIterator: AsyncChannel<WebSocketStreamEvent>.AsyncIterator

        init(events: AsyncChannel<WebSocketStreamEvent>) {
            self.eventIterator = events.makeAsyncIterator()
        }

        mutating func next() async throws -> String? {
            while let event = await eventIterator.next() {
                switch event {
                case let .text(text):
                    return text
                case let .error(error):
                    throw error
                case .disconnected:
                    return nil
                default:
                    continue
                }
            }
            return nil
        }
    }
}
