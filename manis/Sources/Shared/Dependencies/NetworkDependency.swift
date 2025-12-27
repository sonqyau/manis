import Dependencies

struct NetworkInspectorClient {
    var isConnectSetToMihomo: @Sendable (_ httpPort: Int, _ socksPort: Int, _ strict: Bool) async
        -> Bool
    var getPrimaryInterfaceName: @Sendable () async -> String?
    var getPrimaryIPAddress: @Sendable (_ allowIPv6: Bool) async -> String?
}

enum NetworkInspectorClientKey: DependencyKey {
    static let liveValue = NetworkInspectorClient(
        isConnectSetToMihomo: { httpPort, socksPort, strict in
            await MainActor.run {
                let networkDomain = NetworkDomain()
                return networkDomain.isConnectSetToMihomo(
                    httpPort: Port(httpPort),
                    socksPort: Port(socksPort),
                    strict: strict,
                )
            }
        },
        getPrimaryInterfaceName: {
            await MainActor.run {
                let networkDomain = NetworkDomain()
                return networkDomain.getPrimaryInterfaceName()
            }
        },
        getPrimaryIPAddress: { allowIPv6 in
            await MainActor.run {
                let networkDomain = NetworkDomain()
                return networkDomain.getPrimaryIPAddress(allowIPv6: allowIPv6)
            }
        },
    )
}

extension DependencyValues {
    var networkInspector: NetworkInspectorClient {
        get { self[NetworkInspectorClientKey.self] }
        set { self[NetworkInspectorClientKey.self] = newValue }
    }
}

struct NetworkDependency {}
