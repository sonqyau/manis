import Foundation

private final class XPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }
}

private final class ContinuationBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

@MainActor
protocol XPC {
    func getVersion() async throws -> String
    func getKernelStatus() async throws -> ManisKernelStatus
    func startKernel(executablePath: String, configPath: String, configContent: String) async throws
    func stopKernel() async throws
}

enum KernelControlError: Error, LocalizedError {
    case remote(MainXPCError)

    var errorDescription: String? {
        switch self {
        case let .remote(err):
            err.message
        }
    }
}

@MainActor
struct XPCClient: XPC {
    private let machServiceName = "com.manis.XPC"

    private func isRetryableXPCError(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == 4097 {
            return true
        }
        if ns.domain == "com.manis.XPC", ns.code == -1 {
            return true
        }
        return false
    }

    private func withOneRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard isRetryableXPCError(error) else { throw error }
            return try await operation()
        }
    }

    private nonisolated func makeConnection(
        continuationBox: ContinuationBox<some Sendable>,
    ) -> (MainXPCProtocol, NSXPCConnection) {
        let conn = NSXPCConnection(machServiceName: machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: MainXPCProtocol.self)

        conn.invalidationHandler = {
            continuationBox.resume(throwing: NSError(domain: "com.manis.XPC", code: -4097))
        }
        conn.interruptionHandler = {
            continuationBox.resume(throwing: NSError(domain: "com.manis.XPC", code: -4098))
        }

        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            continuationBox.resume(throwing: error)
        }

        guard let service = proxy as? MainXPCProtocol else {
            continuationBox.resume(throwing: NSError(domain: "com.manis.XPC", code: -1))
            return (DummyXPC() as MainXPCProtocol, conn)
        }

        return (service, conn)
    }

    func getVersion() async throws -> String {
        try await withOneRetry {
            try await withCheckedThrowingContinuation { cont in
                let box = ContinuationBox(cont)
                let (service, connection) = makeConnection(continuationBox: box)
                let connBox = XPCConnectionBox(connection)

                service.getVersion { version in
                    box.resume(returning: version)
                    DispatchQueue.main.async {
                        connBox.connection.invalidate()
                    }
                }
            }
        }
    }

    func getKernelStatus() async throws -> ManisKernelStatus {
        try await withOneRetry {
            try await withCheckedThrowingContinuation { cont in
                let box = ContinuationBox(cont)
                let (service, connection) = makeConnection(continuationBox: box)
                let connBox = XPCConnectionBox(connection)

                service.getKernelStatus { status in
                    box.resume(returning: status)
                    DispatchQueue.main.async {
                        connBox.connection.invalidate()
                    }
                }
            }
        }
    }

    func startKernel(executablePath: String, configPath: String, configContent: String) async throws {
        try await withOneRetry {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                let box = ContinuationBox(cont)
                let (service, connection) = makeConnection(continuationBox: box)
                let connBox = XPCConnectionBox(connection)

                service.startKernel(executablePath: executablePath, configPath: configPath, configContent: configContent) { _, error in
                    if let error {
                        box.resume(throwing: KernelControlError.remote(error))
                    } else {
                        box.resume(returning: ())
                    }
                    DispatchQueue.main.async {
                        connBox.connection.invalidate()
                    }
                }
            }
        }
    }

    func stopKernel() async throws {
        try await withOneRetry {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                let box = ContinuationBox(cont)
                let (service, connection) = makeConnection(continuationBox: box)
                let connBox = XPCConnectionBox(connection)

                service.stopKernel { error in
                    if let error {
                        box.resume(throwing: KernelControlError.remote(error))
                    } else {
                        box.resume(returning: ())
                    }
                    DispatchQueue.main.async {
                        connBox.connection.invalidate()
                    }
                }
            }
        }
    }
}

@objc private final class DummyXPC: NSObject, MainXPCProtocol {
    func getVersion(reply: @escaping (String) -> Void) { reply("") }
    func getKernelStatus(reply: @escaping (ManisKernelStatus) -> Void) {
        reply(ManisKernelStatus(isRunning: false, processId: 0, externalController: nil, secret: nil))
    }

    func startKernel(
        executablePath _: String,
        configPath _: String,
        configContent _: String,
        reply: @escaping (String?, MainXPCError?) -> Void,
    ) { reply(nil, MainXPCError(domain: "com.manis.XPC", code: -1, message: "XPC service unavailable")) }

    func stopKernel(reply: @escaping (MainXPCError?) -> Void) {
        reply(MainXPCError(domain: "com.manis.XPC", code: -1, message: "XPC service unavailable"))
    }
}
