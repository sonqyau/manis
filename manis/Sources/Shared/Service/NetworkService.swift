import Foundation

@MainActor
protocol NetworkService: Sendable {
    func startMonitoring()
    func stopMonitoring()
    func getPrimaryInterfaceName() -> String?
    func getPrimaryIPAddress(allowIPv6: Bool) -> String?
    func isSystemProxySetToMihomo(httpPort: Int, socksPort: Int, strict: Bool) -> Bool
}

@MainActor
final class NetworkDomainServiceAdapter: NetworkService, @unchecked Sendable {
    private let domain: NetworkDomain

    init(domain: NetworkDomain = .shared) {
        self.domain = domain
    }

    func startMonitoring() {
        domain.startMonitoring()
    }

    func stopMonitoring() {
        domain.stopMonitoring()
    }

    func getPrimaryInterfaceName() -> String? {
        domain.getPrimaryInterfaceName()
    }

    func getPrimaryIPAddress(allowIPv6: Bool = false) -> String? {
        domain.getPrimaryIPAddress(allowIPv6: allowIPv6)
    }

    func isSystemProxySetToMihomo(httpPort: Int, socksPort: Int, strict: Bool) -> Bool {
        domain.isSystemProxySetToMihomo(httpPort: httpPort, socksPort: socksPort, strict: strict)
    }
}
