import DifferenceKit
import Foundation
import Tagged

enum PortTag {}
enum ProcessIDTag {}
enum ProxyNameTag {}
enum ConnectionIDTag {}
enum ConfigPathTag {}

typealias Port = Tagged<PortTag, Int>
typealias ProcessID = Tagged<ProcessIDTag, Int32>
typealias ProxyName = Tagged<ProxyNameTag, String>
typealias ConnectionID = Tagged<ConnectionIDTag, String>
typealias ConfigPath = Tagged<ConfigPathTag, String>

struct ClashConfig: Codable {
    let port: Port?
    let socksPort: Port?
    let mixedPort: Port?
    let allowLan: Bool
    let bindAddress: String?
    let mode: String?
    let logLevel: String?
    let ipv6: Bool
    let externalController: String?
    let externalUI: String?
    let secret: String?

    enum CodingKeys: String, CodingKey {
        case port
        case socksPort = "socks-port"
        case mixedPort = "mixed-port"
        case allowLan = "allow-lan"
        case bindAddress = "bind-address"
        case mode
        case logLevel = "log-level"
        case ipv6
        case externalController = "external-controller"
        case externalUI = "external-ui"
        case secret
    }

    init(
        port: Port? = nil,
        socksPort: Port? = nil,
        mixedPort: Port? = nil,
        allowLan: Bool = false,
        bindAddress: String? = nil,
        mode: String? = nil,
        logLevel: String? = nil,
        ipv6: Bool = false,
        externalController: String? = nil,
        externalUI: String? = nil,
        secret: String? = nil,
    ) {
        self.port = port
        self.socksPort = socksPort
        self.mixedPort = mixedPort
        self.allowLan = allowLan
        self.bindAddress = bindAddress
        self.mode = mode
        self.logLevel = logLevel
        self.ipv6 = ipv6
        self.externalController = externalController
        self.externalUI = externalUI
        self.secret = secret
    }
}

struct ConfigUpdateRequest: Codable {
    let path: String?
    let payload: String?
}

struct ProxiesResponse: Codable {
    let proxies: [String: ProxyInfo]
}

struct ProxyInfo: Codable, Differentiable {
    let name: ProxyName
    let type: String
    let udp: Bool
    let now: String?
    let all: [ProxyName]
    let history: [ProxyDelay]

    var differenceIdentifier: ProxyName {
        name
    }

    func isContentEqual(to source: Self) -> Bool {
        type == source.type &&
            udp == source.udp &&
            now == source.now &&
            all == source.all &&
            history.count == source.history.count
    }

    init(
        name: ProxyName,
        type: String,
        udp: Bool = false,
        now: String? = nil,
        all: [ProxyName] = [],
        history: [ProxyDelay] = [],
    ) {
        self.name = name
        self.type = type
        self.udp = udp
        self.now = now
        self.all = all
        self.history = history
    }
}

struct ProxyDelay: Codable {
    let time: Date
    let delay: Int
}

struct ProxyDelayTest: Codable {
    let delay: Int
}

struct ProxySelectRequest: Codable {
    let name: ProxyName
}

struct GroupsResponse: Codable {
    let proxies: [String: GroupInfo]
}

struct GroupInfo: Codable, Differentiable {
    let name: ProxyName
    let type: String
    let now: String?
    let all: [ProxyName]

    var differenceIdentifier: ProxyName {
        name
    }

    func isContentEqual(to source: Self) -> Bool {
        type == source.type &&
            now == source.now &&
            all == source.all
    }

    init(
        name: ProxyName,
        type: String,
        now: String? = nil,
        all: [ProxyName] = [],
    ) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
    }
}

struct RulesResponse: Codable {
    let rules: [RuleInfo]
}

struct RuleInfo: Codable, Differentiable {
    let type: String
    let payload: String
    let proxy: ProxyName

    var differenceIdentifier: String {
        "\(type)::\(payload)::\(proxy)"
    }

    func isContentEqual(to source: Self) -> Bool {
        type == source.type &&
            payload == source.payload &&
            proxy == source.proxy
    }
}

struct ProxyProvidersResponse: Codable {
    let providers: [String: ProxyProviderInfo]
}

struct ProxyProviderInfo: Codable, Differentiable {
    let name: ProxyName
    let type: String
    let vehicleType: String
    let proxies: [ProxyInfo]
    let updatedAt: Date?

    var differenceIdentifier: ProxyName {
        name
    }

    func isContentEqual(to source: Self) -> Bool {
        type == source.type &&
            vehicleType == source.vehicleType &&
            proxies.count == source.proxies.count &&
            updatedAt == source.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case name, type, proxies
        case vehicleType
        case updatedAt
    }
}

struct RuleProvidersResponse: Codable {
    let providers: [String: RuleProviderInfo]
}

struct RuleProviderInfo: Codable, Differentiable {
    let name: ProxyName
    let type: String
    let vehicleType: String
    let behavior: String
    let ruleCount: Int
    let updatedAt: Date?

    var differenceIdentifier: ProxyName {
        name
    }

    func isContentEqual(to source: Self) -> Bool {
        type == source.type &&
            vehicleType == source.vehicleType &&
            behavior == source.behavior &&
            ruleCount == source.ruleCount &&
            updatedAt == source.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case name, type, behavior
        case vehicleType
        case ruleCount
        case updatedAt
    }
}

struct LogMessage: Codable, Identifiable {
    let id = UUID()
    let type: String
    let payload: String

    enum CodingKeys: String, CodingKey {
        case type, payload
    }
}

struct DNSQueryRequest: Codable {
    let name: String
    let type: String
}

struct DNSQueryResponse: Codable {
    struct DNSQuestion: Codable {
        let name: String
        let qtype: Int
        let qclass: Int
    }

    struct DNSAnswer: Codable {
        let name: String
        let type: Int
        let ttl: Int
        let data: String
    }

    let status: Int
    let question: [DNSQuestion]
    let answer: [DNSAnswer]

    init(
        status: Int,
        question: [DNSQuestion],
        answer: [DNSAnswer] = [],
    ) {
        self.status = status
        self.question = question
        self.answer = answer
    }
}

struct APIError: Codable, Error {
    let message: String
}
