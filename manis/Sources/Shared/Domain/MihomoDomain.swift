import AsyncAlgorithms
import Clocks
import Collections
@preconcurrency import Combine
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Observation
import OSLog
import Perception
import Sharing

@MainActor
@Observable
final class MihomoDomain {
    struct State {
        var trafficHistory: Deque<TrafficPoint>
        var currentTraffic: TrafficSnapshot?
        var connections: [ConnectionSnapshot.Connection]
        var memoryUsage: Int64
        var version: String
        var logs: Deque<LogMessage>
        var proxies: OrderedDictionary<String, ProxyInfo>
        var groups: OrderedDictionary<String, GroupInfo>
        var rules: [RuleInfo]
        var proxyProviders: OrderedDictionary<String, ProxyProviderInfo>
        var ruleProviders: OrderedDictionary<String, RuleProviderInfo>
        var config: ClashConfig?
        var isConnected: Bool
    }

    @ObservationIgnored
    @Shared(.inMemory("mihomoState")) private var sharedState: State = .init(
        trafficHistory: [],
        currentTraffic: nil,
        connections: [],
        memoryUsage: 0,
        version: "",
        logs: [],
        proxies: [:],
        groups: [:],
        rules: [],
        proxyProviders: [:],
        ruleProviders: [:],
        config: nil,
        isConnected: false,
        )

    @ObservationIgnored
    @Shared(.inMemory("mihomoConnection")) private var connectionInfo: ConnectionInfo = .init()

    struct ConnectionInfo: Equatable {
        var baseURL: String = "http://127.0.0.1:9090"
        var secret: String?
    }

    private let logger = MainLog.shared.logger(for: .api)
    private let clock: any Clock<Duration>

    private let stateSubject: CurrentValueSubject<State, Never>

    private(set) var trafficHistory: Deque<TrafficPoint> = [] {
        didSet { emitState() }
    }

    private(set) var currentTraffic: TrafficSnapshot? {
        didSet { emitState() }
    }

    private(set) var connections: [ConnectionSnapshot.Connection] = [] {
        didSet { emitState() }
    }

    private(set) var memoryUsage: Int64 = 0 {
        didSet { emitState() }
    }

    private(set) var version: String = "" {
        didSet { emitState() }
    }

    private(set) var logs: Deque<LogMessage> = [] {
        didSet { emitState() }
    }

    private(set) var proxies: OrderedDictionary<String, ProxyInfo> = [:] {
        didSet { emitState() }
    }

    private(set) var groups: OrderedDictionary<String, GroupInfo> = [:] {
        didSet { emitState() }
    }

    private(set) var rules: [RuleInfo] = [] {
        didSet { emitState() }
    }

    private(set) var proxyProviders: OrderedDictionary<String, ProxyProviderInfo> = [:] {
        didSet { emitState() }
    }

    private(set) var ruleProviders: OrderedDictionary<String, RuleProviderInfo> = [:] {
        didSet { emitState() }
    }

    private(set) var config: ClashConfig? {
        didSet { emitState() }
    }

    private(set) var isConnected = false {
        didSet { emitState() }
    }

    private var trafficSocket: WebSocketStreamClient?
    private var memorySocket: WebSocketStreamClient?
    private var logSocket: WebSocketStreamClient?
    private var connectionTask: Task<Void, Never>?
    private var dataRefreshTask: Task<Void, Never>?

    private static let maxTrafficPoints = 120
    private static let maxLogEntries = 500

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        let initialState = State(
            trafficHistory: [],
            currentTraffic: nil,
            connections: [],
            memoryUsage: 0,
            version: "",
            logs: [],
            proxies: [:],
            groups: [:],
            rules: [],
            proxyProviders: [:],
            ruleProviders: [:],
            config: nil,
            isConnected: false,
            )
        stateSubject = CurrentValueSubject(initialState)
    }

    nonisolated func configure(baseURL: String, secret: String?) {
        Task { @MainActor in
            $connectionInfo.withLock { connectionInfo in
                connectionInfo.baseURL = baseURL
                connectionInfo.secret = secret
            }
        }
    }

    func connect() async {
        guard !isConnected else {
            return
        }

        await startTrafficStream()
        await startMemoryStream()
        startConnectionPolling()
        startDataRefresh()
        fetchVersion()

        isConnected = true
    }

    func disconnect() {
        trafficSocket?.disconnect(closeCode: nil)
        memorySocket?.disconnect(closeCode: nil)
        logSocket?.disconnect(closeCode: nil)
        connectionTask?.cancel()
        dataRefreshTask?.cancel()

        trafficSocket = nil
        memorySocket = nil
        logSocket = nil
        connectionTask = nil
        dataRefreshTask = nil
        isConnected = false
    }

    func statePublisher() -> AnyPublisher<State, Never> {
        stateSubject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func currentState() -> State {
        stateSubject.value
    }

    func requestDashboardRefresh() {
        Task(priority: .utility) { @MainActor in
            await self.refreshDashboardData()
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    private var state: State {
        State(
            trafficHistory: trafficHistory,
            currentTraffic: currentTraffic,
            connections: connections,
            memoryUsage: memoryUsage,
            version: version,
            logs: logs,
            proxies: proxies,
            groups: groups,
            rules: rules,
            proxyProviders: proxyProviders,
            ruleProviders: ruleProviders,
            config: config,
            isConnected: isConnected,
            )
    }

    private func emitState() {
        stateSubject.send(state)
    }

    private func startDataRefresh() {
        dataRefreshTask?.cancel()
        dataRefreshTask = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            await refreshDashboardData()

            let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                Task {
                    await self.refreshDashboardData()
                }
            }

            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshDashboardData() async {
        await fetchProxies()
        await fetchGroups()
        await fetchRules()
        await fetchProxyProviders()
        await fetchRuleProviders()
        await fetchConfig()
    }

    private func makeRequest(
        path: String,
        method: HTTPRequest.Method = .get,
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        ) async throws -> (Data, HTTPURLResponse) {
        let currentConnection = connectionInfo
        var components = URLComponents(string: "\(currentConnection.baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = HTTPRequest(method: method, url: url)

        if let secret = currentConnection.secret {
            request.headerFields = [
                HTTPField.Name.authorization: "Bearer \(secret)",
            ]
        }

        if body != nil {
            request.headerFields[.contentType] = "application/json"
        }

        if let body {
            request.headerFields[.contentLength] = "\(body.count)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode >= 400 {
            if let error = try? JSONDecoder().decode(APIError.self, from: data) {
                throw error
            }
            throw URLError(.badServerResponse)
        }

        return (data, httpResponse)
    }

    private func startTrafficStream() async {
        let currentConnection = connectionInfo
        guard let url = URL(string: "\(currentConnection.baseURL)/traffic".replacingOccurrences(of: "http", with: "ws"))
        else {
            return
        }

        var request = HTTPRequest(method: .get, url: url)
        if let secret = currentConnection.secret {
            request.headerFields[.authorization] = "Bearer \(secret)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            logger.error("Failed to create URLRequest for traffic socket")
            return
        }
        let client = URLSessionWebSocketStreamClient(request: urlRequest, reconnectionConfig: .default)
        trafficSocket = client
        client.connect()

        let events = client.events
        let stream = events.compactMap { event -> TrafficSnapshot? in
            switch event {
            case let .text(text):
                guard let data = text.data(using: .utf8),
                      let traffic = try? JSONDecoder().decode(TrafficSnapshot.self, from: data)
                else {
                    return nil
                }
                return traffic
            default:
                return nil
            }
        }
        .removeDuplicates { $0.up == $1.up && $0.down == $1.down }

        for try await traffic in stream {
            currentTraffic = traffic

            let point = TrafficPoint(
                timestamp: Date(),
                upload: Double(traffic.up),
                download: Double(traffic.down),
                )

            trafficHistory.append(point)

            if trafficHistory.count > Self.maxTrafficPoints {
                trafficHistory.removeFirst()
            }
        }
    }

    private func startConnectionPolling() {
        connectionTask?.cancel()
        connectionTask = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task {
                    await self.fetchConnections()
                }
            }

            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func startMemoryStream() async {
        let currentConnection = connectionInfo
        guard let url = URL(string: "\(currentConnection.baseURL)/memory".replacingOccurrences(of: "http", with: "ws"))
        else {
            return
        }

        var request = HTTPRequest(method: .get, url: url)
        if let secret = currentConnection.secret {
            request.headerFields[.authorization] = "Bearer \(secret)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            logger.error("Failed to create URLRequest for memory socket")
            return
        }
        let client = URLSessionWebSocketStreamClient(request: urlRequest, reconnectionConfig: .default)
        memorySocket = client
        client.connect()

        let events = client.events
        let stream = events.compactMap { event -> MemorySnapshot? in
            switch event {
            case let .text(text):
                guard let data = text.data(using: .utf8),
                      let memory = try? JSONDecoder().decode(MemorySnapshot.self, from: data)
                else {
                    return nil
                }
                return memory
            default:
                return nil
            }
        }
        .removeDuplicates { $0.inuse == $1.inuse }

        for try await memory in stream {
            memoryUsage = memory.inuse
        }
    }

    private func fetchConnections() async {
        let currentConnection = connectionInfo
        guard let url = URL(string: "\(currentConnection.baseURL)/connections") else {
            return
        }

        var request = HTTPRequest(method: .get, url: url)
        if let secret = currentConnection.secret {
            request.headerFields[.authorization] = "Bearer \(secret)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            logger.error("Failed to create URLRequest for connections fetch")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                if let date = DateFormatting.parseISO8601(dateString) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date format.",
                    )
            }
            let snapshot = try decoder.decode(ConnectionSnapshot.self, from: data)
            connections = snapshot.connections
        } catch {
            logger.error("Failed to fetch connections snapshot.", error: error)
        }
    }

    private func fetchVersion() {
        let currentConnection = connectionInfo
        guard let url = URL(string: "\(currentConnection.baseURL)/version") else {
            return
        }

        var request = HTTPRequest(method: .get, url: url)
        if let secret = currentConnection.secret {
            request.headerFields[.authorization] = "Bearer \(secret)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            logger.error("Failed to create URLRequest for version fetch")
            return
        }

        Task(name: "Fetch Mihomo Version") {
            do {
                let (data, _) = try await URLSession.shared.data(for: urlRequest)
                let versionInfo = try JSONDecoder().decode(ClashVersion.self, from: data)
                await MainActor.run {
                    self.version = versionInfo.version
                    self.logger.info("Fetched Mihomo version.", metadata: ["version": versionInfo.version])
                }
            } catch {
                self.logger.error("Failed to fetch Mihomo version.", error: error)
            }
        }
    }

    private func fetchProxies() async {
        do {
            let (data, _) = try await makeRequest(path: "/proxies")
            let response = try JSONDecoder().decode(ProxiesResponse.self, from: data)
            proxies = OrderedDictionary(uniqueKeysWithValues: response.proxies)
        } catch {
            logger.error("Failed to fetch proxies from API.", error: error)
        }
    }

    private func fetchGroups() async {
        do {
            let (data, _) = try await makeRequest(path: "/group")
            let response = try JSONDecoder().decode(GroupsResponse.self, from: data)
            groups = OrderedDictionary(uniqueKeysWithValues: response.proxies)
        } catch {
            logger.error("Failed to fetch proxy groups from API.", error: error)
        }
    }

    private func fetchRules() async {
        do {
            let (data, _) = try await makeRequest(path: "/rules")
            let response = try JSONDecoder().decode(RulesResponse.self, from: data)
            rules = response.rules
        } catch {
            logger.error("Failed to fetch rules from API.", error: error)
        }
    }

    private func fetchProxyProviders() async {
        do {
            let (data, _) = try await makeRequest(path: "/providers/proxies")
            let response = try JSONDecoder().decode(ProxyProvidersResponse.self, from: data)
            proxyProviders = OrderedDictionary(uniqueKeysWithValues: response.providers)
        } catch {
            logger.error("Failed to fetch proxy providers from API.", error: error)
        }
    }

    private func fetchRuleProviders() async {
        do {
            let (data, _) = try await makeRequest(path: "/providers/rules")
            let response = try JSONDecoder().decode(RuleProvidersResponse.self, from: data)
            ruleProviders = OrderedDictionary(uniqueKeysWithValues: response.providers)
        } catch {
            logger.error("Failed to fetch rule providers from API.", error: error)
        }
    }

    private func fetchConfig() async {
        do {
            let (data, _) = try await makeRequest(path: "/configs")
            config = try JSONDecoder().decode(ClashConfig.self, from: data)
        } catch {
            let chain = error.errorChainDescription
            logger.error("Failed to fetch configuration.\n\(chain)", error: error)
        }
    }

    func startLogStream(level: String? = nil) async {
        let currentConnection = connectionInfo
        var path = "/logs"
        if let level {
            path += "?level=\(level)"
        }

        guard let url = URL(string: "\(currentConnection.baseURL)\(path)".replacingOccurrences(of: "http", with: "ws"))
        else {
            return
        }

        var request = HTTPRequest(method: .get, url: url)
        if let secret = currentConnection.secret {
            request.headerFields[.authorization] = "Bearer \(secret)"
        }

        guard let urlRequest = URLRequest(httpRequest: request) else {
            logger.error("Failed to create URLRequest for log socket")
            return
        }
        let client = URLSessionWebSocketStreamClient(request: urlRequest, reconnectionConfig: .disabled)
        logSocket = client
        client.connect()

        let stream = WebSocketMessageStream(events: client.events)

        do {
            for try await text in stream {
                guard let data = text.data(using: .utf8),
                      let log = try? JSONDecoder().decode(LogMessage.self, from: data)
                else {
                    continue
                }

                logs.append(log)

                if logs.count > Self.maxLogEntries {
                    logs.removeFirst()
                }
            }
        } catch {
            logger.debug("Log stream error.", error: error)
        }
    }

    func stopLogStream() {
        logSocket?.disconnect(closeCode: nil)
        logSocket = nil
    }

    func getConfig() async throws -> ClashConfig {
        let (data, _) = try await makeRequest(path: "/configs")
        return try JSONDecoder().decode(ClashConfig.self, from: data)
    }

    func reloadConfig(path: String = "", payload: String = "") async throws {
        let request = ConfigUpdateRequest(path: path, payload: payload)
        let body = try JSONEncoder().encode(request)
        _ = try await makeRequest(
            path: "/configs",
            method: .put,
            body: body,
            queryItems: [URLQueryItem(name: "force", value: "true")],
            )
        logger.info("Reloaded Config")
        await fetchConfig()
    }

    func updateConfig(_ updates: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: updates)
        _ = try await makeRequest(path: "/configs", method: .patch, body: body)
        logger.info("Updated Config")
        await fetchConfig()
    }

    func upgradeGeo2() async throws {
        _ = try await makeRequest(path: "/configs/geo", method: .post, body: Data())
        logger.info("Updated GEO database")
    }

    func restart() async throws {
        _ = try await makeRequest(path: "/restart", method: .post, body: Data())
        logger.info("Restarted core")
    }

    func upgradeCore() async throws {
        _ = try await makeRequest(path: "/upgrade", method: .post, body: Data())
        logger.info("Upgraded core")
    }

    func upgradeUI() async throws {
        _ = try await makeRequest(path: "/upgrade/ui", method: .post, body: Data())
        logger.info("Upgraded UI")
    }

    func upgradeGeo1() async throws {
        _ = try await makeRequest(path: "/upgrade/geo", method: .post, body: Data())
        logger.info("Upgraded GEO database")
    }

    func flushFakeIPCache() async throws {
        _ = try await makeRequest(path: "/cache/fakeip/flush", method: .post, body: Data())
        logger.info("Flushed fake IP cache")
    }

    func closeAllConnections() async throws {
        _ = try await makeRequest(path: "/connections", method: .delete)
        logger.info("Closed all connections")
        await fetchConnections()
    }

    func closeConnection(id: ConnectionID) async throws {
        _ = try await makeRequest(path: "/connections/\(id.rawValue)", method: .delete)
        logger.info("Closed connection: \(id.rawValue)")
        await fetchConnections()
    }

    func selectProxy(group: ProxyName, proxy: ProxyName) async throws {
        let encodedGroup = group.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group.rawValue
        let request = ProxySelectRequest(name: proxy)
        let body = try JSONEncoder().encode(request)
        _ = try await makeRequest(path: "/proxies/\(encodedGroup)", method: .put, body: body)
        logger.info("Selected proxy \(proxy.rawValue) for group \(group.rawValue)")
        await fetchProxies()
        await fetchGroups()
    }

    func testProxyDelay(
        name: ProxyName,
        url: String = "https://www.apple.com/library/test/success.html",
        timeout: Int = 5000,
        ) async throws -> ProxyDelayTest {
        let encodedName = name.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.rawValue
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
        ]
        let (data, _) = try await makeRequest(
            path: "/proxies/\(encodedName)/delay",
            queryItems: queryItems,
            )
        return try JSONDecoder().decode(ProxyDelayTest.self, from: data)
    }

    func testGroupDelay(
        name: ProxyName,
        url: String = "https://www.apple.com/library/test/success.html",
        timeout: Int = 5000,
        ) async throws {
        let encodedName = name.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.rawValue
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
        ]
        _ = try await makeRequest(path: "/group/\(encodedName)/delay", queryItems: queryItems)
        logger.info("Tested group delay: \(name.rawValue)")
        await fetchGroups()
    }

    func updateProxyProvider(name: ProxyName) async throws {
        let encodedName = name.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.rawValue
        _ = try await makeRequest(
            path: "/providers/proxies/\(encodedName)",
            method: .put,
            body: Data(),
            )
        logger.info("Updated proxy provider: \(name.rawValue)")
        await fetchProxyProviders()
    }

    func healthCheckProxyProvider(name: ProxyName) async throws {
        let encodedName = name.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.rawValue
        _ = try await makeRequest(path: "/providers/proxies/\(encodedName)/healthcheck")
        logger.info("Health check for proxy provider: \(name.rawValue)")
        await fetchProxyProviders()
    }

    func updateRuleProvider(name: ProxyName) async throws {
        let encodedName = name.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.rawValue
        _ = try await makeRequest(path: "/providers/rules/\(encodedName)", method: .put, body: Data())
        logger.info("Updated rule provider: \(name.rawValue)")
        await fetchRuleProviders()
    }

    func queryDNS(name: String, type: String = "A") async throws -> DNSQueryResponse {
        let queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type),
        ]
        let (data, _) = try await makeRequest(path: "/dns/query", queryItems: queryItems)
        return try JSONDecoder().decode(DNSQueryResponse.self, from: data)
    }

    func triggerGC() async throws {
        _ = try await makeRequest(path: "/debug/gc", method: .put, body: Data())
        logger.info("Triggered garbage collection")
    }

    func flushDNSCache() async throws {
        _ = try await makeRequest(path: "/cache/dns/flush", method: .post, body: Data())
        logger.info("Flushed DNS cache")
    }
}
