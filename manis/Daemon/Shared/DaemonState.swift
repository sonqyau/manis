import Foundation

enum DaemonState: Sendable {
    case idle
    case initializing
    case running
    case error(DaemonError)
}

enum MihomoState: Sendable {
    case stopped
    case starting
    case running(ProcessInfo)
    case stopping
    case error(Error)
}

enum ConnectState: Sendable {
    case disabled
    case enabling
    case enabled(ProxyConfiguration)
    case disabling
    case error(Error)
}

enum DNSState: Sendable {
    case `default`
    case configuring
    case configured(DNSConfiguration)
    case error(Error)
}

struct ProcessInfo: Sendable {
    let pid: Int32
    let startTime: Date
    let configPath: String
    let externalController: String?
    let secret: String?
}

struct ProxyConfiguration: Sendable {
    let httpPort: Int
    let socksPort: Int
    let pacURL: String?
    let bypassList: [String]
}

struct DNSConfiguration: Sendable {
    let servers: [String]
    let hijackEnabled: Bool
}

enum DaemonError: Error, Sendable {
    case invalidStateTransition(from: String, to: String)
    case serviceUnavailable(String)
    case configurationError(String)
    case processError(String)
    case networkError(String)

    var localizedDescription: String {
        switch self {
        case let .invalidStateTransition(from, to):
            "Invalid state transition from \(from) to \(to)"
        case let .serviceUnavailable(service):
            "Service unavailable: \(service)"
        case let .configurationError(message):
            "Configuration error: \(message)"
        case let .processError(message):
            "Process error: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        }
    }
}
