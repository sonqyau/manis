import AppKit
import AsyncQueue
import CFNetwork
import Clocks
import Foundation
import Network
import NonEmpty
import OSLog
import Sharing
import SystemConfiguration

extension Notification.Name {
    static let systemProxyDidChange = Notification.Name("com.manis.systemProxyDidChange")
    static let networkInterfaceDidChange = Notification.Name("com.manis.networkInterfaceDidChange")
    static let systemDidWakeFromSleep = Notification.Name("com.manis.systemDidWakeFromSleep")
}

@MainActor
final class NetworkDomain {
    @ObservationIgnored
    @Shared(.inMemory("networkState")) private var networkState: NetworkState = .init()

    struct NetworkState {
        var currentPath: NWPath?
        var primaryInterface: String?
        var primaryIPAddress: String?
        var isMonitoring: Bool = false
    }

    private let logger = MainLog.shared.logger(for: .network)
    private let clock: any Clock<Duration>

    private var pathMonitor: NWPathMonitor?
    private let queue = FIFOQueue(name: "NetworkDomain")
    private let monitorQueue = DispatchQueue(label: "com.manis.network.monitor", qos: .utility)

    private var proxyStore: SCDynamicStore?
    private var ipStore: SCDynamicStore?

    private var isMonitoring = false

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func startMonitoring() {
        guard !isMonitoring else {
            return
        }

        startPathMonitoring()

        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    await self?.startProxyMonitoring()
                }
                group.addTask { [weak self] in
                    await self?.startIPMonitoring()
                }
            }
        }

        startSleepWakeMonitoring()

        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else {
            return
        }

        pathMonitor?.cancel()
        pathMonitor = nil

        if let store = proxyStore {
            SCDynamicStoreSetDispatchQueue(store, nil)
            proxyStore = nil
        }

        if let store = ipStore {
            SCDynamicStoreSetDispatchQueue(store, nil)
            ipStore = nil
        }

        NSWorkspace.shared.notificationCenter.removeObserver(self)

        isMonitoring = false
    }

    private func startPathMonitoring() {
        let monitor = NWPathMonitor()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                $networkState.withLock { networkState in
                    networkState.currentPath = path
                }

                logger.debug(
                    "Network path state changed",
                    metadata: [
                        "status": path.status.description,
                        "interfaces": "\(path.availableInterfaces.count)",
                    ],
                    )

                if let interface = path.availableInterfaces.first {
                    $networkState.withLock { networkState in
                        networkState.primaryInterface = interface.name
                    }
                }

                NotificationCenter.default.post(name: .networkInterfaceDidChange, object: self)
            }
        }

        monitor.start(queue: monitorQueue)
        pathMonitor = monitor

        logger.info("Path monitor started")
    }

    private func startProxyMonitoring() async {
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else {
                return
            }
            let monitor = Unmanaged<NetworkDomain>.fromOpaque(info).takeUnretainedValue()

            Task { @MainActor in
                monitor.logger.debug("System proxy configuration changed")
                NotificationCenter.default.post(name: .systemProxyDidChange, object: monitor)
            }
        }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
            )

        guard
            let store = SCDynamicStoreCreate(
                kCFAllocatorDefault,
                "com.manis.proxy.monitor" as CFString,
                callback,
                &context,
                )
        else {
            await MainActor.run {
                logger.error("Failed to create SCDynamicStore for proxy monitoring")
            }
            return
        }

        let keys = ["State:/Network/Global/Proxies"] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, nil, keys) else {
            await MainActor.run {
                logger.error("Failed to set notification keys for proxy monitoring")
            }
            return
        }

        guard SCDynamicStoreSetDispatchQueue(store, monitorQueue) else {
            await MainActor.run {
                logger.error("Failed to set dispatch queue for proxy monitoring")
            }
            return
        }

        await MainActor.run {
            self.proxyStore = store
            logger.info("Proxy configuration monitoring started")
        }
    }

    private func startIPMonitoring() async {
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else {
                return
            }
            let monitor = Unmanaged<NetworkDomain>.fromOpaque(info).takeUnretainedValue()

            Task { @MainActor in
                monitor.logger.debug("IP address changed")
                monitor.updatePrimaryIPAddress()
                NotificationCenter.default.post(name: .networkInterfaceDidChange, object: monitor)
            }
        }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
            )

        guard
            let store = SCDynamicStoreCreate(
                kCFAllocatorDefault,
                "com.manis.ip.monitor" as CFString,
                callback,
                &context,
                )
        else {
            await MainActor.run {
                logger.error("Failed to create SCDynamicStore for IP monitoring")
            }
            return
        }

        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, nil, keys) else {
            await MainActor.run {
                logger.error("Failed to set notification keys for IP monitoring")
            }
            return
        }

        guard SCDynamicStoreSetDispatchQueue(store, monitorQueue) else {
            await MainActor.run {
                logger.error("Failed to set dispatch queue for IP monitoring")
            }
            return
        }

        await MainActor.run {
            self.ipStore = store
            logger.info("IP address monitoring started")
        }
    }

    private func startSleepWakeMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil,
            )

        logger.info("Sleep and wake monitoring started")
    }

    @objc private func handleSystemWake(_: Notification) {
        logger.info("System wake detected")

        NotificationCenter.default.post(name: .networkInterfaceDidChange, object: self)

        Task(priority: .utility) { @MainActor in
            try? await clock.sleep(for: .seconds(1))
            NotificationCenter.default.post(name: .systemDidWakeFromSleep, object: self)
            self.logger.debug("Wake notification posted")
        }
    }

    func getPrimaryInterfaceName() -> String? {
        if let cached = networkState.primaryInterface {
            return cached
        }

        guard let store = SCDynamicStoreCreate(nil, "com.manis.query" as CFString, nil, nil) else {
            return nil
        }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetIPv4,
            )

        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let iface = dict[kSCDynamicStorePropNetPrimaryInterface as String] as? String
        else { return nil }

        $networkState.withLock { networkState in
            networkState.primaryInterface = iface
        }
        return iface
    }

    func getDNSServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "com.manis.query" as CFString, nil, nil) else {
            return []
        }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetDNS,
            )

        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let servers = dict[kSCPropNetDNSServerAddresses as String] as? [String]
        else { return [] }

        return servers
    }

    func getPrimaryIPAddress(allowIPv6: Bool = false) -> String? {
        if let cached = networkState.primaryIPAddress, !allowIPv6 {
            return cached
        }
        guard let ifName = getPrimaryInterfaceName() else {
            return nil
        }

        guard let store = SCDynamicStoreCreate(nil, "com.manis.query" as CFString, nil, nil) else {
            return nil
        }

        let ipv4Key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil, kSCDynamicStoreDomainState, ifName as CFString, kSCEntNetIPv4,
            )
        if let ipv4Info = SCDynamicStoreCopyValue(store, ipv4Key) as? [String: Any],
           let addresses = ipv4Info[kSCPropNetIPv4Addresses as String] as? [String],
           let nonEmptyAddresses = NonEmpty(rawValue: addresses),
           let first = nonEmptyAddresses.first {
            $networkState.withLock { networkState in
                networkState.primaryIPAddress = first
            }
            return first
        }

        guard allowIPv6 else {
            return nil
        }

        let ipv6Key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil, kSCDynamicStoreDomainState, ifName as CFString, kSCEntNetIPv6,
            )
        guard let ipv6Info = SCDynamicStoreCopyValue(store, ipv6Key) as? [String: Any],
              let addresses = ipv6Info[kSCPropNetIPv6Addresses as String] as? [String],
              let nonEmptyAddresses = NonEmpty(rawValue: addresses),
              let first = nonEmptyAddresses.first
        else {
            return nil
        }

        return "[\(first)]"
    }

    func getConnectSettings() -> [String: Any] {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    func isConnectSetToMihomo(httpPort: Port, socksPort: Port, strict: Bool = true) -> Bool {
        let settings = getConnectSettings()
        let http = settings[kCFNetworkProxiesHTTPPort as String] as? Int ?? 0
        let https = settings[kCFNetworkProxiesHTTPSPort as String] as? Int ?? 0
        let socks = settings[kCFNetworkProxiesSOCKSPort as String] as? Int ?? 0

        return strict
            ? (http == httpPort.rawValue && https == httpPort.rawValue && socks == socksPort.rawValue)
            : (http == httpPort.rawValue || https == httpPort.rawValue || socks == socksPort.rawValue)
    }

    private func updatePrimaryIPAddress() {
        $networkState.withLock { networkState in
            networkState.primaryIPAddress = getPrimaryIPAddress(allowIPv6: false)
        }
    }
}

extension NWPath.Status {
    var description: String {
        switch self {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown"
        }
    }
}
