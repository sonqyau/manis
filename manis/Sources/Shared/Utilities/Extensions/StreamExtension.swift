import Clocks
import Foundation
import Starscream

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

final class StarscreamWebSocketStreamClient: NSObject, WebSocketStreamClient, WebSocketDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let reconnectionConfig: WebSocketReconnectionConfig
    private let clock: any Clock<Duration>
    private var socket: WebSocket?
    private var continuation: AsyncStream<WebSocketStreamEvent>.Continuation?
    private let callbackQueue: DispatchQueue
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
        callbackQueue: DispatchQueue = .main,
        ) {
        self.request = request
        self.reconnectionConfig = reconnectionConfig
        self.clock = clock
        self.callbackQueue = callbackQueue
        self._currentDelay = reconnectionConfig.initialDelay
        super.init()
        setupSocket()
    }

    private func setupSocket() {
        let socket = WebSocket(request: request)
        socket.callbackQueue = callbackQueue
        socket.delegate = self
        self.socket = socket
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
        socket?.connect()
    }

    func disconnect(closeCode: UInt16? = nil) {
        stateQueue.async(flags: .barrier) {
            self._isManuallyDisconnected = true
        }
        reconnectTask?.cancel()
        stateQueue.async(flags: .barrier) {
            self._reconnectTask = nil
        }

        if let code = closeCode {
            socket?.disconnect(closeCode: code)
        } else {
            socket?.disconnect()
        }
        continuation?.finish()
    }

    func send(text: String) {
        socket?.write(string: text)
    }

    func send(data: Data) {
        socket?.write(data: data)
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
                self.setupSocket()
                self.socket?.connect()
            }
        }

        stateQueue.async(flags: .barrier) {
            self._reconnectTask = task
        }
    }

    func didReceive(event: Starscream.WebSocketEvent, client _: Starscream.WebSocketClient) {
        switch event {
        case let .connected(headers):
            stateQueue.async(flags: .barrier) {
                self._reconnectAttempt = 0
                self._currentDelay = self.reconnectionConfig.initialDelay
            }
            reconnectTask?.cancel()
            stateQueue.async(flags: .barrier) {
                self._reconnectTask = nil
            }
            continuation?.yield(.connected(headers: headers))

        case let .disconnected(reason, code):
            continuation?.yield(.disconnected(reason: reason, code: code))
            if !isManuallyDisconnected {
                scheduleReconnect()
            } else {
                continuation?.finish()
            }

        case let .text(text):
            continuation?.yield(.text(text))

        case let .binary(data):
            continuation?.yield(.data(data))

        case let .error(error):
            if let error {
                continuation?.yield(.error(error))
            }
            if !isManuallyDisconnected {
                scheduleReconnect()
            } else {
                continuation?.finish()
            }

        case .cancelled:
            continuation?.yield(.disconnected(reason: "cancelled", code: 0))
            if !isManuallyDisconnected {
                scheduleReconnect()
            } else {
                continuation?.finish()
            }

        case .reconnectSuggested:
            if !isManuallyDisconnected {
                scheduleReconnect()
            }

        case .viabilityChanged, .ping, .pong, .peerClosed:
            break
        }
    }
}

struct TrafficDataStream: AsyncSequence {
    typealias Element = TrafficSnapshot

    private let events: AsyncStream<WebSocketStreamEvent>

    init(events: AsyncStream<WebSocketStreamEvent>) {
        self.events = events
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(baseIterator: events.makeAsyncIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var baseIterator: AsyncStream<WebSocketStreamEvent>.Iterator

        init(baseIterator: AsyncStream<WebSocketStreamEvent>.Iterator) {
            self.baseIterator = baseIterator
        }

        mutating func next() async throws -> TrafficSnapshot? {
            while let event = await baseIterator.next() {
                switch event {
                case let .text(text):
                    guard let data = text.data(using: .utf8) else {
                        continue
                    }
                    return try JSONDecoder().decode(TrafficSnapshot.self, from: data)

                case let .data(data):
                    return try JSONDecoder().decode(TrafficSnapshot.self, from: data)

                case let .error(error):
                    throw error

                case let .disconnected(reason, code):
                    throw NSError(
                        domain: "WebSocketStream",
                        code: Int(code),
                        userInfo: [NSLocalizedDescriptionKey: reason ?? "WebSocket disconnected"],
                        )

                case .connected:
                    continue
                }
            }

            return nil
        }
    }
}

struct WebSocketMessageStream: AsyncSequence {
    typealias Element = String

    private let events: AsyncStream<WebSocketStreamEvent>

    init(events: AsyncStream<WebSocketStreamEvent>) {
        self.events = events
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(baseIterator: events.makeAsyncIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var baseIterator: AsyncStream<WebSocketStreamEvent>.Iterator

        init(baseIterator: AsyncStream<WebSocketStreamEvent>.Iterator) {
            self.baseIterator = baseIterator
        }

        mutating func next() async throws -> String? {
            while let event = await baseIterator.next() {
                switch event {
                case let .text(text):
                    return text

                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        return text
                    } else {
                        continue
                    }

                case let .error(error):
                    throw error

                case let .disconnected(reason, code):
                    throw NSError(
                        domain: "WebSocketStream",
                        code: Int(code),
                        userInfo: [NSLocalizedDescriptionKey: reason ?? "WebSocket disconnected"],
                        )

                case .connected:
                    continue
                }
            }

            return nil
        }
    }
}
