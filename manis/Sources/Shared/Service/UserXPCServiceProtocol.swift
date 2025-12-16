import Foundation

@objc protocol MainXPCProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func getKernelStatus(reply: @escaping (ManisKernelStatus) -> Void)
    func startKernel(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (String?, MainXPCError?) -> Void,
    )
    func stopKernel(reply: @escaping (MainXPCError?) -> Void)
}

@objc final class MainXPCError: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    @objc let domain: String
    @objc let code: Int
    @objc let message: String

    init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
        super.init()
    }

    convenience init(error: any Error) {
        let ns = error as NSError
        self.init(domain: ns.domain, code: ns.code, message: ns.localizedDescription)
    }

    required init?(coder: NSCoder) {
        domain = coder.decodeObject(of: NSString.self, forKey: "domain") as String? ?? "unknown"
        code = coder.decodeInteger(forKey: "code")
        message = coder.decodeObject(of: NSString.self, forKey: "message") as String? ?? "Unknown error"
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(domain, forKey: "domain")
        coder.encode(code, forKey: "code")
        coder.encode(message, forKey: "message")
    }
}

extension MainXPCError: @unchecked Sendable {}

@objc final class ManisKernelStatus: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    @objc let isRunning: Bool
    @objc let processId: Int32
    @objc let externalController: String?
    @objc let secret: String?

    init(isRunning: Bool, processId: Int32, externalController: String?, secret: String?) {
        self.isRunning = isRunning
        self.processId = processId
        self.externalController = externalController
        self.secret = secret
        super.init()
    }

    required init?(coder: NSCoder) {
        isRunning = coder.decodeBool(forKey: "isRunning")
        processId = coder.decodeInt32(forKey: "processId")
        externalController = coder.decodeObject(of: NSString.self, forKey: "externalController") as String?
        secret = coder.decodeObject(of: NSString.self, forKey: "secret") as String?
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(isRunning, forKey: "isRunning")
        coder.encode(processId, forKey: "processId")
        coder.encode(externalController, forKey: "externalController")
        coder.encode(secret, forKey: "secret")
    }
}

extension ManisKernelStatus: @unchecked Sendable {}
