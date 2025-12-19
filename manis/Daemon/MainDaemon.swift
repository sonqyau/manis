import Cocoa
import ConcurrencyExtras
import OSLog

class MainDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private var listener: NSXPCListener
    private var connections = [NSXPCConnection]()
    private let shouldQuit = LockIsolated(false)
    private var shouldQuitCheckInterval = 2.0

    private let mihomoManager = MihomoDaemon()
    private let systemProxyManager = SystemProxyDaemon()
    private let dnsManager = DNSDaemon()

    override init() {
        listener = NSXPCListener(machServiceName: "com.manis.Daemon")
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        os_log("MainDaemon running")
        while true {
            if shouldQuit.value { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: shouldQuitCheckInterval))
        }
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValid(connection: newConnection) else {
            return false
        }

        let connectionID = ObjectIdentifier(newConnection)

        newConnection.exportedInterface = NSXPCInterface(with: MainDaemonProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.connections.removeAll { ObjectIdentifier($0) == connectionID }
                let isEmpty = self.connections.isEmpty
                if isEmpty {
                    self.shouldQuit.setValue(true)
                }
                if isEmpty {
                    os_log("MainDaemon shouldQuit")
                }
            }
        }

        connections.append(newConnection)
        newConnection.resume()

        return true
    }

    private func isValid(connection: NSXPCConnection) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier) else {
            os_log("MainDaemon rejected connection: pid=%d not a running app", connection.processIdentifier)
            return false
        }

        guard let bundleIdentifier = app.bundleIdentifier else {
            os_log("MainDaemon accepted connection: pid=%d bundleIdentifier=nil", connection.processIdentifier)
            return true
        }

        if bundleIdentifier == "com.manis.app" || bundleIdentifier == "com.manis.XPC" {
            return true
        }

        os_log("MainDaemon rejected connection: pid=%d bundleIdentifier=%{public}@", connection.processIdentifier, bundleIdentifier)
        return false
    }
}

private struct SendableReplyWrapper<T>: @unchecked Sendable {
    let reply: (T) -> Void

    init(_ reply: @escaping (T) -> Void) {
        self.reply = reply
    }

    func callAsFunction(_ value: T) {
        reply(value)
    }
}

extension MainDaemon: MainDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        reply(version)
    }

    func startMihomo(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (String?, String?) -> Void,
        ) {
        let wrappedReply = SendableReplyWrapper(reply)

        mihomoManager.start(
            executablePath: executablePath,
            configPath: configPath,
            configContent: configContent,
            ) { result in
            Task { @MainActor in
                switch result {
                case let .success(message):
                    wrappedReply((message, nil))
                case let .failure(error):
                    wrappedReply((nil, error.localizedDescription))
                }
            }
        }
    }

    func stopMihomo(reply: @escaping (String?) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        mihomoManager.stop { result in
            Task { @MainActor in
                switch result {
                case .success:
                    wrappedReply(nil)
                case let .failure(error):
                    wrappedReply(error.localizedDescription)
                }
            }
        }
    }

    func getMihomoStatus(reply: @escaping (MihomoStatus) -> Void) {
        let status = mihomoManager.getStatus()
        let objcStatus = MihomoStatus(
            isRunning: status.isRunning,
            processId: status.processId ?? 0,
            startTime: status.startTime,
            configPath: status.configPath,
            externalController: status.externalController,
            secret: status.secret,
            logs: status.logs,
            )
        reply(objcStatus)
    }

    func restartMihomo(reply: @escaping (String?, String?) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        mihomoManager.restart { result in
            Task { @MainActor in
                switch result {
                case let .success(message):
                    wrappedReply((message, nil))
                case let .failure(error):
                    wrappedReply((nil, error.localizedDescription))
                }
            }
        }
    }

    func enableSystemProxy(
        httpPort: Int,
        socksPort: Int,
        pacURL: String?,
        bypassList: [String],
        reply: @escaping (String?) -> Void,
        ) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            self.systemProxyManager.enableProxy(
                httpPort: httpPort,
                socksPort: socksPort,
                pacURL: pacURL,
                bypassList: bypassList,
                ) { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        wrappedReply(nil)
                    case let .failure(error):
                        wrappedReply(error.localizedDescription)
                    }
                }
            }
        }
    }

    func disableSystemProxy(reply: @escaping (String?) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            self.systemProxyManager.disableProxy { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        wrappedReply(nil)
                    case let .failure(error):
                        wrappedReply(error.localizedDescription)
                    }
                }
            }
        }
    }

    func getSystemProxyStatus(reply: @escaping (SystemProxyStatus) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            let status = self.systemProxyManager.getStatus()
            let objcStatus = SystemProxyStatus(
                isEnabled: status.isEnabled,
                httpProxy: status.httpProxy.map { SystemProxyInfo(host: $0.host, port: $0.port) },
                httpsProxy: status.httpsProxy.map { SystemProxyInfo(host: $0.host, port: $0.port) },
                socksProxy: status.socksProxy.map { SystemProxyInfo(host: $0.host, port: $0.port) },
                pacURL: status.pacURL,
                bypassList: status.bypassList,
                )
            wrappedReply(objcStatus)
        }
    }

    func configureDNS(
        servers: [String],
        hijackEnabled: Bool,
        reply: @escaping (String?) -> Void,
        ) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            self.dnsManager.configure(
                servers: servers,
                hijackEnabled: hijackEnabled,
                ) { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        wrappedReply(nil)
                    case let .failure(error):
                        wrappedReply(error.localizedDescription)
                    }
                }
            }
        }
    }

    func flushDNSCache(reply: @escaping (String?) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            self.dnsManager.flushCache { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        wrappedReply(nil)
                    case let .failure(error):
                        wrappedReply(error.localizedDescription)
                    }
                }
            }
        }
    }

    func getUsedPorts(reply: @escaping ([Int]) -> Void) {
        let wrappedReply = SendableReplyWrapper(reply)

        Task { @MainActor in
            let ports = NetworkDaemon.getUsedPorts()
            wrappedReply(ports)
        }
    }

    func testConnectivity(
        host: String,
        port: Int,
        timeout: TimeInterval,
        reply: @escaping (Bool) -> Void,
        ) {
        let wrappedReply = SendableReplyWrapper(reply)

        NetworkDaemon.testConnectivity(
            host: host,
            port: port,
            timeout: timeout,
            ) { isReachable in
            Task { @MainActor in
                wrappedReply(isReachable)
            }
        }
    }

    func updateTun(
        enabled: Bool,
        dnsServer: String,
        reply: @escaping (String?) -> Void,
        ) {
        let wrappedReply = SendableReplyWrapper(reply)

        let status = mihomoManager.getStatus()
        guard let controller = status.externalController, !controller.isEmpty else {
            wrappedReply("Mihomo external controller not available")
            return
        }

        let urlString = "http://\(controller)/configs"
        guard let url = URL(string: urlString) else {
            wrappedReply("Invalid mihomo controller URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = status.secret, !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        var tunObject: [String: Any] = ["enable": enabled]
        if !dnsServer.isEmpty {
            tunObject["dns-server"] = dnsServer
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tun": tunObject])

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                wrappedReply(error.localizedDescription)
                return
            }

            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                wrappedReply("Mihomo API returned status \(http.statusCode)")
                return
            }

            wrappedReply(nil)
        }
        task.resume()
    }
}
