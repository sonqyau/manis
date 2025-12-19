import Foundation

struct SnapshotModel {}

struct MihomoSnapshot {
    var trafficHistory: [TrafficPoint]
    var currentTraffic: TrafficSnapshot?
    var connections: [ConnectionSnapshot.Connection]
    var memoryUsage: Int64
    var version: String
    var logs: [LogMessage]
    var proxies: [String: ProxyInfo]
    var groups: [String: GroupInfo]
    var rules: [RuleInfo]
    var proxyProviders: [String: ProxyProviderInfo]
    var ruleProviders: [String: RuleProviderInfo]
    var config: ClashConfig?
    var isConnected: Bool

    init(_ state: MihomoDomain.State) {
        trafficHistory = state.trafficHistory
        currentTraffic = state.currentTraffic
        connections = state.connections
        memoryUsage = state.memoryUsage
        version = state.version
        logs = state.logs
        proxies = state.proxies
        groups = state.groups
        rules = state.rules
        proxyProviders = state.proxyProviders
        ruleProviders = state.ruleProviders
        config = state.config
        isConnected = state.isConnected
    }
}

struct LaunchSnapshot {
    var isEnabled: Bool
    var requiresApproval: Bool

    init() {
        isEnabled = Bootstrap.isEnabled
        requiresApproval = Bootstrap.requiresApproval
    }
}
