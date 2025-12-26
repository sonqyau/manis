import Foundation
import Tagged

typealias XPCPort = Tagged<XPCTypes, Int>
typealias XPCProcessID = Tagged<XPCTypes, Int32>
typealias XPCConfigPath = Tagged<XPCTypes, String>

struct XPCTypes {}

struct KernelStartRequest: Codable, Sendable {
    let executablePath: XPCConfigPath
    let configPath: XPCConfigPath
    let configContent: String
}

struct ConnectRequest: Codable, Sendable {
    let httpPort: XPCPort
    let socksPort: XPCPort
    let pacURL: String?
    let bypassList: [String]
}

struct DNSRequest: Codable, Sendable {
    let servers: [String]
    let hijackEnabled: Bool
}

struct ConnectivityRequest: Codable, Sendable {
    let host: String
    let port: XPCPort
    let timeout: TimeInterval
}

struct TunRequest: Codable, Sendable {
    let enabled: Bool
    let dnsServer: String
}

struct XPCRequest: Codable, Sendable {
    let method: String
    let executablePath: XPCConfigPath?
    let configPath: XPCConfigPath?
    let configContent: String?
    let httpPort: XPCPort?
    let socksPort: XPCPort?
    let pacURL: String?
    let bypassList: [String]?
    let servers: [String]?
    let hijackEnabled: Bool
    let host: String?
    let port: XPCPort?
    let timeout: TimeInterval?
    let enabled: Bool
    let dnsServer: String?

    init(
        method: String,
        executablePath: XPCConfigPath? = nil,
        configPath: XPCConfigPath? = nil,
        configContent: String? = nil,
        httpPort: XPCPort? = nil,
        socksPort: XPCPort? = nil,
        pacURL: String? = nil,
        bypassList: [String]? = nil,
        servers: [String]? = nil,
        hijackEnabled: Bool = false,
        host: String? = nil,
        port: XPCPort? = nil,
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

struct ManisKernelStatus: Codable, Sendable {
    let isRunning: Bool
    let processId: XPCProcessID
    let externalController: String?
    let secret: String?
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
    let port: XPCPort
}

struct MainXPCError: Error, Codable, Sendable {
    let domain: String
    let code: Int
    let message: String

    init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }

    init(error: any Error) {
        let ns = error as NSError
        self.domain = ns.domain
        self.code = ns.code
        self.message = ns.localizedDescription
    }
}

struct DaemonRequest: Codable, Sendable {
    let method: String
    let executablePath: XPCConfigPath?
    let configPath: XPCConfigPath?
    let configContent: String?
    let httpPort: XPCPort?
    let socksPort: XPCPort?
    let pacURL: String?
    let bypassList: [String]?
    let servers: [String]?
    let hijackEnabled: Bool
    let host: String?
    let port: XPCPort?
    let timeout: TimeInterval?
    let enabled: Bool
    let dnsServer: String?

    init(
        method: String,
        executablePath: XPCConfigPath? = nil,
        configPath: XPCConfigPath? = nil,
        configContent: String? = nil,
        httpPort: XPCPort? = nil,
        socksPort: XPCPort? = nil,
        pacURL: String? = nil,
        bypassList: [String]? = nil,
        servers: [String]? = nil,
        hijackEnabled: Bool = false,
        host: String? = nil,
        port: XPCPort? = nil,
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

enum DaemonResponse: Codable, Sendable {
    case version(String)
    case mihomoStatus(MihomoStatus)
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
        case "mihomoStatus":
            let value = try container.decode(MihomoStatus.self, forKey: .value)
            self = .mihomoStatus(value)
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
        case let .mihomoStatus(value):
            try container.encode("mihomoStatus", forKey: .type)
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

struct MihomoStatus: Codable, Sendable {
    let isRunning: Bool
    let processId: XPCProcessID
    let startTime: Date?
    let configPath: XPCConfigPath?
    let externalController: String?
    let secret: String?
    let logs: [String]
}
