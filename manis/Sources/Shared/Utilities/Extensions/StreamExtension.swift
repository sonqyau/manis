import Clocks
import Foundation

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
    case connected(headers: [String: String]?)
    case disconnected(reason: String?, code: UInt16)
    case text(String)
    case data(Data)
    case error(Error)
}

protocol WebSocketStreamClient: AnyObject {
    var events: AsyncStream<WebSocketStreamEvent> { get }

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
    private var continuation: AsyncStream<WebSocketStreamEvent>.Continuation?
    private let stateQueue = DispatchQueue(label: "com.manis.websocket.state", attributes: .concurrent)

    private var _isManuallyDisconnected = false
    private var _reconnectTask: Task<Void, Never>?
    private var _reconnectAttempt = 0
    private var _currentDelay: TimeInterval

    private var isManuallyDisconnected: Bool {
        get { stateQueue.sync { _isManuallyDisconnected } }
        set { stateQueue.async(flags: .barrier) { self._isManuallyDisconnected = newValue } }
    }

    private var reconnectTask: Task<Void, Never>? {
        get { stateQueue.sync { _reconnectTask } }
        set { stateQueue.async(flags: .barrier) { self._reconnectTask = newValue } }
    }

    private var currentDelay: TimeInterval {
        get { stateQueue.sync { _currentDelay } }
        set { stateQueue.async(flags: .barrier) { self._currentDelay = newValue } }
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

    private(set) lazy var events: AsyncStream<WebSocketStreamEvent> = AsyncStream { continuation in
        self.continuation = continuation
    }

    func connect() {
        stateQueue.async(flags: .barrier) {
            self._isManuallyDisconnected = false
            self._reconnectAttempt = 0
            self._currentDelay = self.reconnectionConfig.initialDelay
        }
        reconnectTask?.cancel()
        stateQueue.async(flags: .barrier) {
            self._reconnectTask = nil
        }

        setupWebSocket()
        webSocketTask?.resume()
        startReceiving()
    }

    func disconnect(closeCode: UInt16? = nil) {
        stateQueue.async(flags: .barrier) {
            self._isManuallyDisconnected = true
        }
        reconnectTask?.cancel()
        stateQueue.async(flags: .barrier) {
            self._reconnectTask = nil
        }

        let closeCode = closeCode.map { URLSessionWebSocketTask.CloseCode(rawValue: Int($0)) ?? .normalClosure } ?? .normalClosure
        webSocketTask?.cancel(with: closeCode, reason: nil)
        continuation?.finish()
    }

    func send(text: String) {
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error {
                self?.continuation?.yield(.error(error))
            }
        }
    }

    func send(data: Data) {
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error {
                self?.continuation?.yield(.error(error))
            }
        }
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(message):
                switch message {
                case let .string(text):
                    self.continuation?.yield(.text(text))
                case let .data(data):
                    self.continuation?.yield(.data(data))
                @unknown default:
                    break
                }
                self.startReceiving()

            case let .failure(error):
                self.continuation?.yield(.error(error))
                if !self.isManuallyDisconnected {
                    self.scheduleReconnect()
                } else {
                    self.continuation?.finish()
                }
            }
        }
    }

    private func scheduleReconnect() {
        let shouldReconnect = stateQueue.sync {
            reconnectionConfig.enabled && !_isManuallyDisconnected
        }

        guard shouldReconnect else {
            continuation?.finish()
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

            let stillShouldReconnect = self.stateQueue.sync {
                !self._isManuallyDisconnected
            }

            guard stillShouldReconnect else {
                return
            }

            self.stateQueue.sync(flags: .barrier) {
                self._reconnectAttempt += 1
                self._currentDelay = min(
                    self._currentDelay * backoffMultiplier,
                    maxDelay,
                    )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.setupWebSocket()
                self.webSocketTask?.resume()
                self.startReceiving()
            }
        }

        stateQueue.async(flags: .barrier) {
            self._reconnectTask = task
        }
    }
}

extension URLSessionWebSocketStreamClient: URLSessionWebSocketDelegate {
    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        let headers: [String: String]? = nil
        continuation?.yield(.connected(headers: headers))

        stateQueue.async(flags: .barrier) {
            self._reconnectAttempt = 0
            self._currentDelay = self.reconnectionConfig.initialDelay
        }
        reconnectTask?.cancel()
        stateQueue.async(flags: .barrier) {
            self._reconnectTask = nil
        }
    }

    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        continuation?.yield(.disconnected(reason: reasonString, code: UInt16(closeCode.rawValue)))

        if !isManuallyDisconnected {
            scheduleReconnect()
        } else {
            continuation?.finish()
        }
    }
}

struct TrafficDataStream: AsyncSequence {
    typealias Element = TrafficSnapshot

    let events: AsyncStream<WebSocketStreamEvent>

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(events: events)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var eventIterator: AsyncStream<WebSocketStreamEvent>.AsyncIterator

        init(events: AsyncStream<WebSocketStreamEvent>) {
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

    let events: AsyncStream<WebSocketStreamEvent>

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(events: events)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var eventIterator: AsyncStream<WebSocketStreamEvent>.AsyncIterator

        init(events: AsyncStream<WebSocketStreamEvent>) {
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
