import Foundation

@objc protocol MainDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)

    func startMihomo(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (String?, String?) -> Void,
    )

    func stopMihomo(reply: @escaping (String?) -> Void)

    func getMihomoStatus(reply: @escaping (MihomoStatus) -> Void)

    func restartMihomo(reply: @escaping (String?, String?) -> Void)

    func enableSystemProxy(
        httpPort: Int,
        socksPort: Int,
        pacURL: String?,
        bypassList: [String],
        reply: @escaping (String?) -> Void,
    )

    func disableSystemProxy(reply: @escaping (String?) -> Void)

    func getSystemProxyStatus(reply: @escaping (SystemProxyStatus) -> Void)

    func configureDNS(
        servers: [String],
        hijackEnabled: Bool,
        reply: @escaping (String?) -> Void,
    )

    func flushDNSCache(reply: @escaping (String?) -> Void)

    func getUsedPorts(reply: @escaping ([Int]) -> Void)

    func testConnectivity(
        host: String,
        port: Int,
        timeout: TimeInterval,
        reply: @escaping (Bool) -> Void,
    )
}

@objc class MihomoStatus: NSObject, NSSecureCoding {
    static let supportsSecureCoding: Bool = true

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

@objc class SystemProxyInfo: NSObject, NSSecureCoding {
    static let supportsSecureCoding: Bool = true

    @objc let host: String
    @objc let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
        super.init()
    }

    required init?(coder: NSCoder) {
        host = coder.decodeObject(of: NSString.self, forKey: "host") as String? ?? ""
        port = coder.decodeInteger(forKey: "port")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(host, forKey: "host")
        coder.encode(port, forKey: "port")
    }
}

@objc class SystemProxyStatus: NSObject, NSSecureCoding {
    static let supportsSecureCoding: Bool = true

    @objc let isEnabled: Bool
    @objc let httpProxy: SystemProxyInfo?
    @objc let httpsProxy: SystemProxyInfo?
    @objc let socksProxy: SystemProxyInfo?
    @objc let pacURL: String?
    @objc let bypassList: [String]

    init(
        isEnabled: Bool,
        httpProxy: SystemProxyInfo?,
        httpsProxy: SystemProxyInfo?,
        socksProxy: SystemProxyInfo?,
        pacURL: String?,
        bypassList: [String],
    ) {
        self.isEnabled = isEnabled
        self.httpProxy = httpProxy
        self.httpsProxy = httpsProxy
        self.socksProxy = socksProxy
        self.pacURL = pacURL
        self.bypassList = bypassList
        super.init()
    }

    required init?(coder: NSCoder) {
        isEnabled = coder.decodeBool(forKey: "isEnabled")
        httpProxy = coder.decodeObject(of: SystemProxyInfo.self, forKey: "httpProxy")
        httpsProxy = coder.decodeObject(of: SystemProxyInfo.self, forKey: "httpsProxy")
        socksProxy = coder.decodeObject(of: SystemProxyInfo.self, forKey: "socksProxy")
        pacURL = coder.decodeObject(of: NSString.self, forKey: "pacURL") as String?
        bypassList = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "bypassList") as? [String] ?? []
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(isEnabled, forKey: "isEnabled")
        coder.encode(httpProxy, forKey: "httpProxy")
        coder.encode(httpsProxy, forKey: "httpsProxy")
        coder.encode(socksProxy, forKey: "socksProxy")
        coder.encode(pacURL, forKey: "pacURL")
        coder.encode(bypassList, forKey: "bypassList")
    }
}
