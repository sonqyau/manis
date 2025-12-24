import Combine
import Foundation

@MainActor
protocol MihomoService: AnyObject, Sendable {
    var statePublisher: AnyPublisher<MihomoDomain.State, Never> { get }

    func configure(baseURL: String, secret: String?)
    func connect() async
    func disconnect()
    func currentState() -> MihomoDomain.State
    func requestDashboardRefresh()
    func selectProxy(group: String, proxy: String) async throws
    func closeConnection(id: String) async throws
    func closeAllConnections() async throws
    func testGroupDelay(name: String) async throws
    func startLogStream(level: String?) async
    func stopLogStream()
    func clearLogs()
    func reloadConfig(path: String, payload: String) async throws
    func queryDNS(name: String, type: String) async throws -> DNSQueryResponse
    func updateProxyProvider(name: String) async throws
    func healthCheckProxyProvider(name: String) async throws
    func updateRuleProvider(name: String) async throws
    func flushDNSCache() async throws
    func flushFakeIPCache() async throws
    func restart() async throws
    func upgradeCore() async throws
    func upgradeUI() async throws
    func upgradeGeo1() async throws
    func upgradeGeo2() async throws
    func triggerGC() async throws
    func updateConfig(_ updates: [String: Any]) async throws
}

@MainActor
final class APIDomainMihomoServiceAdapter: MihomoService, @unchecked Sendable {
    private let domain: MihomoDomain

    init(domain: MihomoDomain = .shared) {
        self.domain = domain
    }

    var statePublisher: AnyPublisher<MihomoDomain.State, Never> {
        domain.statePublisher()
    }

    func configure(baseURL: String, secret: String?) {
        domain.configure(baseURL: baseURL, secret: secret)
    }

    func connect() async {
        await domain.connect()
    }

    func disconnect() {
        domain.disconnect()
    }

    func currentState() -> MihomoDomain.State {
        domain.currentState()
    }

    func requestDashboardRefresh() {
        domain.requestDashboardRefresh()
    }

    func selectProxy(group: String, proxy: String) async throws {
        try await domain.selectProxy(group: group, proxy: proxy)
    }

    func closeConnection(id: String) async throws {
        try await domain.closeConnection(id: id)
    }

    func closeAllConnections() async throws {
        try await domain.closeAllConnections()
    }

    func testGroupDelay(name: String) async throws {
        _ = try await domain.testGroupDelay(name: name)
    }

    func startLogStream(level: String?) async {
        await domain.startLogStream(level: level)
    }

    func stopLogStream() {
        domain.stopLogStream()
    }

    func clearLogs() {
        domain.clearLogs()
    }

    func reloadConfig(path: String, payload: String) async throws {
        try await domain.reloadConfig(path: path, payload: payload)
    }

    func queryDNS(name: String, type: String) async throws -> DNSQueryResponse {
        try await domain.queryDNS(name: name, type: type)
    }

    func updateProxyProvider(name: String) async throws {
        try await domain.updateProxyProvider(name: name)
    }

    func healthCheckProxyProvider(name: String) async throws {
        try await domain.healthCheckProxyProvider(name: name)
    }

    func updateRuleProvider(name: String) async throws {
        try await domain.updateRuleProvider(name: name)
    }

    func flushDNSCache() async throws {
        try await domain.flushDNSCache()
    }

    func restart() async throws {
        try await domain.restart()
    }

    func upgradeCore() async throws {
        try await domain.upgradeCore()
    }

    func upgradeUI() async throws {
        try await domain.upgradeUI()
    }

    func upgradeGeo1() async throws {
        try await domain.upgradeGeo1()
    }

    func upgradeGeo2() async throws {
        try await domain.upgradeGeo2()
    }

    func flushFakeIPCache() async throws {
        try await domain.flushFakeIPCache()
    }

    func triggerGC() async throws {
        try await domain.triggerGC()
    }

    func updateConfig(_ updates: [String: Any]) async throws {
        try await domain.updateConfig(updates)
    }
}
