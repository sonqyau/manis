import AsyncQueue
import ConcurrencyExtras
import Foundation
import OSLog
import SwiftyXPC

struct XPCRequest: Codable, Sendable {
    let method: String
    let executablePath: String?
    let configPath: String?
    let configContent: String?
    let httpPort: Int?
    let socksPort: Int?
    let pacURL: String?
    let bypassList: [String]?
    let servers: [String]?
    let hijackEnabled: Bool
    let host: String?
    let port: Int?
    let timeout: TimeInterval?
    let enabled: Bool
    let dnsServer: String?

    init(
        method: String,
        executablePath: String? = nil,
        configPath: String? = nil,
        configContent: String? = nil,
        httpPort: Int? = nil,
        socksPort: Int? = nil,
        pacURL: String? = nil,
        bypassList: [String]? = nil,
        servers: [String]? = nil,
        hijackEnabled: Bool = false,
        host: String? = nil,
        port: Int? = nil,
        timeout: TimeInterval? = nil,
        enabled: Bool = false,
        dnsServer: String? = nil,
    ) {
        self.method = method
        self.executablePath = executablePath
        self.configPath = configPath
        self.configContent = configContent
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.pacURL = pacURL
        self.bypassList = bypassList
        self.servers = servers
        self.hijackEnabled = hijackEnabled
        self.host = host
        self.port = port
        self.timeout = timeout
        self.enabled = enabled
        self.dnsServer = dnsServer
    }
}

enum XPCResponse: Codable, Sendable {
    case version(String)
    case kernelStatus(ManisKernelStatus)
    case systemProxyStatus(ConnectStatus)
    case usedPorts([Int])
    case connectivity(Bool)
    case message(String)
    case error(MainXPCError)

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "version":
            let value = try container.decode(String.self, forKey: .value)
            self = .version(value)
        case "kernelStatus":
            let value = try container.decode(ManisKernelStatus.self, forKey: .value)
            self = .kernelStatus(value)
        case "systemProxyStatus":
            let value = try container.decode(ConnectStatus.self, forKey: .value)
            self = .systemProxyStatus(value)
        case "usedPorts":
            let value = try container.decode([Int].self, forKey: .value)
            self = .usedPorts(value)
        case "connectivity":
            let value = try container.decode(Bool.self, forKey: .value)
            self = .connectivity(value)
        case "message":
            let value = try container.decode(String.self, forKey: .value)
            self = .message(value)
        case "error":
            let value = try container.decode(MainXPCError.self, forKey: .value)
            self = .error(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown response type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .version(value):
            try container.encode("version", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .kernelStatus(value):
            try container.encode("kernelStatus", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .systemProxyStatus(value):
            try container.encode("systemProxyStatus", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .usedPorts(value):
            try container.encode("usedPorts", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .connectivity(value):
            try container.encode("connectivity", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .message(value):
            try container.encode("message", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .error(value):
            try container.encode("error", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct ConnectStatus: Codable, Sendable {
    let isEnabled: Bool
    let httpProxy: ConnectInfo?
    let httpsProxy: ConnectInfo?
    let socksProxy: ConnectInfo?
    let pacURL: String?
    let bypassList: [String]
}

struct ConnectInfo: Codable, Sendable {
    let host: String
    let port: Int32
}

struct KernelStartRequest: Codable, Sendable {
    let executablePath: String
    let configPath: String
    let configContent: String
}

extension ManisKernelStatus: Codable {
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isRunning = try container.decode(Bool.self, forKey: .isRunning)
        let processId = try container.decode(Int32.self, forKey: .processId)
        let externalController = try container.decodeIfPresent(String.self, forKey: .externalController)
        let secret = try container.decodeIfPresent(String.self, forKey: .secret)
        self.init(isRunning: isRunning, processId: processId, externalController: externalController, secret: secret)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(processId, forKey: .processId)
        try container.encodeIfPresent(externalController, forKey: .externalController)
        try container.encodeIfPresent(secret, forKey: .secret)
    }

    private enum CodingKeys: String, CodingKey {
        case isRunning, processId, externalController, secret
    }
}

extension MainXPCError: Codable {
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let domain = try container.decode(String.self, forKey: .domain)
        let code = try container.decode(Int.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)
        self.init(domain: domain, code: code, message: message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case domain, code, message
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
    private let logger = Logger(subsystem: "com.manis.app", category: "XPCClient")
    private let queue = FIFOQueue(name: "XPCClient")

    private func isRetryableXPCError(_ error: any Error) -> Bool {
        let ns = error as NSError

        logger.debug("XPC Error - Domain: \(ns.domain), Code: \(ns.code), Description: \(ns.localizedDescription)")

        if ns.domain == NSCocoaErrorDomain, ns.code == 4097 {
            logger.warning("XPC connection invalidated (NSCocoaErrorDomain 4097)")
            return true
        }
        if ns.domain == "com.manis.XPC", ns.code == -1 {
            logger.warning("XPC service unavailable")
            return true
        }
        if ns.domain == "com.manis.XPC", ns.code == -4097 {
            logger.warning("XPC connection invalidated (custom domain)")
            return true
        }

        if ns.domain == "SMAppServiceErrorDomain" {
            switch ns.code {
            case 3:
                logger.warning("XPC service requires user approval")
                return false
            case 2:
                logger.error("XPC service not found in bundle")
                return false
            default:
                logger.warning("SMAppService error: \(ns.code)")
                return false
            }
        }

        if ns.domain == NSPOSIXErrorDomain, ns.code == ETIMEDOUT {
            logger.warning("XPC operation timed out")
            return true
        }

        if ns.domain == NSPOSIXErrorDomain, ns.code == EPERM {
            logger.error("XPC permission denied")
            return false
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

    func getVersion() async throws -> String {
        try await withOneRetry {
            try await Task(on: queue) {
                let connection = try XPCConnection(type: .remoteMachService(serviceName: machServiceName, isPrivilegedHelperTool: false))
                connection.activate()
                defer { connection.cancel() }

                return try await connection.sendMessage(name: "getVersion")
            }.value
        }
    }

    func getKernelStatus() async throws -> ManisKernelStatus {
        try await withOneRetry {
            try await Task(on: queue) {
                let connection = try XPCConnection(type: .remoteMachService(serviceName: machServiceName, isPrivilegedHelperTool: false))
                connection.activate()
                defer { connection.cancel() }

                let response: XPCResponse = try await connection.sendMessage(name: "getKernelStatus")

                switch response {
                case let .kernelStatus(status):
                    return status
                case let .error(error):
                    throw KernelControlError.remote(error)
                default:
                    throw NSError(domain: "com.manis.XPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response type"])
                }
            }.value
        }
    }

    func startKernel(executablePath: String, configPath: String, configContent: String) async throws {
        try await withOneRetry {
            try await Task(on: queue) {
                let connection = try XPCConnection(type: .remoteMachService(serviceName: machServiceName, isPrivilegedHelperTool: false))
                connection.activate()
                defer { connection.cancel() }

                let request = XPCRequest(
                    method: "startKernel",
                    executablePath: executablePath,
                    configPath: configPath,
                    configContent: configContent,
                )

                let response: XPCResponse = try await connection.sendMessage(name: "startKernel", request: request)

                switch response {
                case .message:
                    return
                case let .error(error):
                    throw KernelControlError.remote(error)
                default:
                    throw NSError(domain: "com.manis.XPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response type"])
                }
            }.value
        }
    }

    func stopKernel() async throws {
        try await withOneRetry {
            try await Task(on: queue) {
                let connection = try XPCConnection(type: .remoteMachService(serviceName: machServiceName, isPrivilegedHelperTool: false))
                connection.activate()
                defer { connection.cancel() }

                let response: XPCResponse = try await connection.sendMessage(name: "stopKernel")

                switch response {
                case .message:
                    return
                case let .error(error):
                    throw KernelControlError.remote(error)
                default:
                    throw NSError(domain: "com.manis.XPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response type"])
                }
            }.value
        }
    }
}
