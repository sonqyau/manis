import Foundation

private final class XPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }
}

@objc protocol MainDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func getMihomoStatus(reply: @escaping (MihomoStatus) -> Void)
    func startMihomo(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (String?, String?) -> Void,
    )
    func stopMihomo(reply: @escaping (String?) -> Void)
}

@objc final class MihomoStatus: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    @objc let isRunning: Bool
    @objc let processId: Int32
    @objc let startTime: Date?
    @objc let configPath: String?
    @objc let externalController: String?
    @objc let secret: String?
    @objc let logs: [String]

    init(
        isRunning: Bool,
        processId: Int32,
        startTime: Date?,
        configPath: String?,
        externalController: String?,
        secret: String?,
        logs: [String],
    ) {
        self.isRunning = isRunning
        self.processId = processId
        self.startTime = startTime
        self.configPath = configPath
        self.externalController = externalController
        self.secret = secret
        self.logs = logs
        super.init()
    }

    required init?(coder: NSCoder) {
        isRunning = coder.decodeBool(forKey: "isRunning")
        processId = coder.decodeInt32(forKey: "processId")
        startTime = coder.decodeObject(of: NSDate.self, forKey: "startTime") as Date?
        configPath = coder.decodeObject(of: NSString.self, forKey: "configPath") as String?
        externalController = coder.decodeObject(of: NSString.self, forKey: "externalController") as String?
        secret = coder.decodeObject(of: NSString.self, forKey: "secret") as String?
        logs = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "logs") as? [String] ?? []
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(isRunning, forKey: "isRunning")
        coder.encode(processId, forKey: "processId")
        coder.encode(startTime, forKey: "startTime")
        coder.encode(configPath, forKey: "configPath")
        coder.encode(externalController, forKey: "externalController")
        coder.encode(secret, forKey: "secret")
        coder.encode(logs, forKey: "logs")
    }
}

extension MihomoStatus: @unchecked Sendable {}

final class DaemonBridge: @unchecked Sendable {
    private let machServiceName = "com.manis.Daemon"
    private var connection: NSXPCConnection?

    func getMihomoStatus(reply: @escaping (Result<MihomoStatus, Error>) -> Void) {
        do {
            let conn = try getOrCreateConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                reply(.failure(error))
            }) as? MainDaemonProtocol else {
                reply(.failure(NSError(domain: "com.manis.XPC", code: -2)))
                return
            }

            proxy.getMihomoStatus { status in
                reply(.success(status))
            }
        } catch {
            reply(.failure(error))
        }
    }

    func startMihomo(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (Result<String, Error>) -> Void,
    ) {
        do {
            let conn = try getOrCreateConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                reply(.failure(error))
            }) as? MainDaemonProtocol else {
                reply(.failure(NSError(domain: "com.manis.XPC", code: -2)))
                return
            }

            proxy.startMihomo(executablePath: executablePath, configPath: configPath, configContent: configContent) { message, error in
                if let error {
                    reply(.failure(NSError(domain: "com.manis.XPC", code: -10, userInfo: [NSLocalizedDescriptionKey: error])))
                } else {
                    reply(.success(message ?? "OK"))
                }
            }
        } catch {
            reply(.failure(error))
        }
    }

    func stopMihomo(reply: @escaping (Result<Void, Error>) -> Void) {
        do {
            let conn = try getOrCreateConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                reply(.failure(error))
            }) as? MainDaemonProtocol else {
                reply(.failure(NSError(domain: "com.manis.XPC", code: -2)))
                return
            }

            proxy.stopMihomo { error in
                if let error {
                    reply(.failure(NSError(domain: "com.manis.XPC", code: -11, userInfo: [NSLocalizedDescriptionKey: error])))
                } else {
                    reply(.success(()))
                }
            }
        } catch {
            reply(.failure(error))
        }
    }

    func getVersion() async throws -> String {
        let helper = try getRemote()
        return try await withCheckedThrowingContinuation { cont in
            helper.getVersion { version in
                cont.resume(returning: version)
            }
        }
    }

    func getMihomoStatus() async throws -> MihomoStatus {
        let helper = try getRemote()
        return try await withCheckedThrowingContinuation { cont in
            helper.getMihomoStatus { status in
                cont.resume(returning: status)
            }
        }
    }

    func startMihomo(executablePath: String, configPath: String, configContent: String) async throws -> String {
        let helper = try getRemote()
        return try await withCheckedThrowingContinuation { cont in
            helper.startMihomo(executablePath: executablePath, configPath: configPath, configContent: configContent) { message, error in
                if let error {
                    cont.resume(throwing: NSError(domain: "com.manis.XPC", code: -10, userInfo: [NSLocalizedDescriptionKey: error]))
                } else {
                    cont.resume(returning: message ?? "OK")
                }
            }
        }
    }

    func stopMihomo() async throws {
        let helper = try getRemote()
        return try await withCheckedThrowingContinuation { cont in
            helper.stopMihomo { error in
                if let error {
                    cont.resume(throwing: NSError(domain: "com.manis.XPC", code: -11, userInfo: [NSLocalizedDescriptionKey: error]))
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func getRemote() throws -> MainDaemonProtocol {
        if let connection {
            return try makeRemote(from: connection)
        }

        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: MainDaemonProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        connection = conn
        return try makeRemote(from: conn)
    }

    private func getOrCreateConnection() throws -> NSXPCConnection {
        if let connection {
            return connection
        }

        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: MainDaemonProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func makeRemote(from conn: NSXPCConnection) throws -> MainDaemonProtocol {
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
        }) as? MainDaemonProtocol else {
            throw NSError(domain: "com.manis.XPC", code: -2)
        }
        return proxy
    }
}
