import Foundation
import OSLog
import SystemConfiguration

struct InternalSystemProxyStatus {
    let isEnabled: Bool
    let httpProxy: InternalProxyInfo?
    let httpsProxy: InternalProxyInfo?
    let socksProxy: InternalProxyInfo?
    let pacURL: String?
    let bypassList: [String]
}

struct InternalProxyInfo {
    let host: String
    let port: Int
}

class SystemProxyDaemon {
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "SystemProxyDaemon")

    func enableProxy(
        httpPort: Int,
        socksPort: Int,
        pacURL: String?,
        bypassList: [String],
        completion: @escaping (Result<Void, Error>) -> Void,
        ) {
        do {
            let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
            guard let store = dynamicStore else {
                throw SystemProxyError.storeCreationFailed
            }

            let services = getNetworkServices()

            for service in services {
                let proxyKey = "State:/Network/Service/\(service)/Proxies" as CFString

                var proxyDict: [String: Any] = [:]

                if let pacURL, !pacURL.isEmpty {
                    proxyDict[kCFNetworkProxiesProxyAutoConfigEnable as String] = 1
                    proxyDict[kCFNetworkProxiesProxyAutoConfigURLString as String] = pacURL
                } else {
                    proxyDict[kCFNetworkProxiesHTTPEnable as String] = 1
                    proxyDict[kCFNetworkProxiesHTTPProxy as String] = "127.0.0.1"
                    proxyDict[kCFNetworkProxiesHTTPPort as String] = httpPort

                    proxyDict[kCFNetworkProxiesHTTPSEnable as String] = 1
                    proxyDict[kCFNetworkProxiesHTTPSProxy as String] = "127.0.0.1"
                    proxyDict[kCFNetworkProxiesHTTPSPort as String] = httpPort

                    if socksPort > 0 {
                        proxyDict[kCFNetworkProxiesSOCKSEnable as String] = 1
                        proxyDict[kCFNetworkProxiesSOCKSProxy as String] = "127.0.0.1"
                        proxyDict[kCFNetworkProxiesSOCKSPort as String] = socksPort
                    }
                }

                if !bypassList.isEmpty {
                    proxyDict[kCFNetworkProxiesExceptionsList as String] = bypassList
                }

                if !SCDynamicStoreSetValue(store, proxyKey, proxyDict as CFDictionary) {
                    throw SystemProxyError.settingsFailed
                }
            }

            logger.info("System proxy enabled successfully")
            completion(.success(()))
        } catch {
            logger.error("Failed to enable system proxy: \(error)")
            completion(.failure(error))
        }
    }

    func disableProxy(completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
            guard let store = dynamicStore else {
                throw SystemProxyError.storeCreationFailed
            }

            let services = getNetworkServices()

            for service in services {
                let proxyKey = "State:/Network/Service/\(service)/Proxies" as CFString

                let proxyDict: [String: Any] = [
                    kCFNetworkProxiesHTTPEnable as String: 0,
                    kCFNetworkProxiesHTTPSEnable as String: 0,
                    kCFNetworkProxiesSOCKSEnable as String: 0,
                    kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
                ]

                if !SCDynamicStoreSetValue(store, proxyKey, proxyDict as CFDictionary) {
                    throw SystemProxyError.settingsFailed
                }
            }

            logger.info("System proxy disabled successfully")
            completion(.success(()))
        } catch {
            logger.error("Failed to disable system proxy: \(error)")
            completion(.failure(error))
        }
    }

    func getStatus() -> InternalSystemProxyStatus {
        let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
        guard let store = dynamicStore else {
            return InternalSystemProxyStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )
        }

        let services = getNetworkServices()
        guard let firstService = services.first else {
            return InternalSystemProxyStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )
        }

        let proxyKey = "State:/Network/Service/\(firstService)/Proxies" as CFString
        guard let proxyDict = SCDynamicStoreCopyValue(store, proxyKey) as? [String: Any] else {
            return InternalSystemProxyStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )
        }

        let httpEnabled = (proxyDict[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1
        let httpsEnabled = (proxyDict[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 1
        let socksEnabled = (proxyDict[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 1
        let pacEnabled = (proxyDict[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Int) == 1

        var httpProxy: InternalProxyInfo?
        var httpsProxy: InternalProxyInfo?
        var socksProxy: InternalProxyInfo?

        if httpEnabled,
           let host = proxyDict[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = proxyDict[kCFNetworkProxiesHTTPPort as String] as? Int {
            httpProxy = InternalProxyInfo(host: host, port: port)
        }

        if httpsEnabled,
           let host = proxyDict[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = proxyDict[kCFNetworkProxiesHTTPSPort as String] as? Int {
            httpsProxy = InternalProxyInfo(host: host, port: port)
        }

        if socksEnabled,
           let host = proxyDict[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = proxyDict[kCFNetworkProxiesSOCKSPort as String] as? Int {
            socksProxy = InternalProxyInfo(host: host, port: port)
        }

        let pacURL = proxyDict[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String
        let bypassList = proxyDict[kCFNetworkProxiesExceptionsList as String] as? [String] ?? []

        return InternalSystemProxyStatus(
            isEnabled: httpEnabled || httpsEnabled || socksEnabled || pacEnabled,
            httpProxy: httpProxy,
            httpsProxy: httpsProxy,
            socksProxy: socksProxy,
            pacURL: pacURL,
            bypassList: bypassList,
            )
    }

    private func getNetworkServices() -> [String] {
        let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
        guard let store = dynamicStore else { return [] }

        let pattern = "State:/Network/Service/[^/]+/IPv4" as CFString
        guard let keys = SCDynamicStoreCopyKeyList(store, pattern) as? [String] else {
            return []
        }

        return keys.compactMap { key in
            let components = key.components(separatedBy: "/")
            return components.count >= 4 ? components[3] : nil
        }
    }
}

enum SystemProxyError: Error, LocalizedError {
    case storeCreationFailed
    case settingsFailed

    var errorDescription: String? {
        switch self {
        case .storeCreationFailed:
            "Failed to create system configuration store"
        case .settingsFailed:
            "Failed to apply proxy settings"
        }
    }
}
