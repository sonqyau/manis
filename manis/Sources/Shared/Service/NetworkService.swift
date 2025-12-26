import Foundation

@MainActor
protocol NetworkService: Sendable {
    func startMonitoring()
    func stopMonitoring()
    func getPrimaryInterfaceName() -> String?
    func getPrimaryIPAddress(allowIPv6: Bool) -> String?
    func isConnectSetToMihomo(httpPort: Int, socksPort: Int, strict: Bool) -> Bool
}

@MainActor
final class NetworkDomainServiceAdapter: NetworkService, @unchecked Sendable {
    private let domain: NetworkDomain

    init(domain: NetworkDomain = NetworkDomain()) {
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

    func isConnectSetToMihomo(httpPort: Int, socksPort: Int, strict: Bool) -> Bool {
        domain.isConnectSetToMihomo(httpPort: Port(httpPort), socksPort: Port(socksPort), strict: strict)
    }
}
