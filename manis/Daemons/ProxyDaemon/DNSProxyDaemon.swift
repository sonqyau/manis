import Foundation
import OSLog
import SystemConfiguration

enum DNSProxyDaemonError: Error, LocalizedError {
  case failedToSetDNS
  case failedToFlushCache
  case failedToCreateTUN
  case noActiveNetworkInterface

  var userFriendlyMessage: String {
    errorDescription ?? "DNS error"
  }

  var errorDescription: String? {
    switch self {
    case .failedToSetDNS:
      "Unable to apply DNS configuration."
    case .failedToFlushCache:
      "Unable to flush the DNS cache."
    case .failedToCreateTUN:
      "Unable to create TUN device."
    case .noActiveNetworkInterface:
      "No active network interface found."
    }
  }
}

final class DNSProxyDaemon {
  @MainActor static let shared = DNSProxyDaemon()

  private let logger = Logger(subsystem: "com.sonqyau.manis.daemon", category: "dns")
  private var customDNS: String = ""
  private var originalDNSSettings: [String: [String: Any]] = [:]

  private init() {}

  func updateTun(enabled: Bool, dnsServer: String) throws {
    customDNS = dnsServer

    if enabled {
      try hijackDNS()
    } else {
      try revertDNS()
    }

    try flushCache()
  }

  private func getActiveNetworkInterfaces() -> [String] {
    var interfaces: [String] = []
    
    guard let prefRef = SCPreferencesCreate(nil, "manis" as CFString, nil),
          let services = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any] else {
      return ["Wi-Fi", "Ethernet"]
    }

    for (_, value) in services {
      guard let service = value as? [String: Any],
            let interface = service["Interface"] as? [String: Any],
            let deviceName = interface["DeviceName"] as? String,
            let type = interface["Type"] as? String else {
        continue
      }

      if type == "Ethernet" || type == "AirPort" || type == "Wi-Fi" {
        interfaces.append(deviceName)
      }
    }

    return interfaces.isEmpty ? ["Wi-Fi", "Ethernet"] : interfaces
  }

  private func backupCurrentDNSSettings() {
    guard let prefRef = SCPreferencesCreate(nil, "manis" as CFString, nil),
          let services = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any] else {
      return
    }

    originalDNSSettings.removeAll()

    for (key, value) in services {
      guard let service = value as? [String: Any],
            let interface = service["Interface"] as? [String: Any],
            let deviceName = interface["DeviceName"] as? String else {
        continue
      }

      let servicePath = "/\(kSCPrefNetworkServices)/\(key)/\(kSCEntNetProxies)" as CFString
      if let dnsSettings = SCPreferencesPathGetValue(prefRef, servicePath) as? [String: Any] {
        originalDNSSettings[deviceName] = dnsSettings
      }
    }
  }

  func hijackDNS() throws {
    guard !customDNS.isEmpty else { return }

    logger.info("Applying custom DNS server: \(self.customDNS)")
    
    backupCurrentDNSSettings()
    
    let interfaces = getActiveNetworkInterfaces()
    var successCount = 0

    for interface in interfaces {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
      task.arguments = ["-setdnsservers", interface, customDNS]

      do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
          successCount += 1
          logger.debug("DNS set successfully for interface: \(interface)")
        } else {
          logger.warning("Failed to set DNS for interface: \(interface)")
        }
      } catch {
        logger.warning("Error setting DNS for interface \(interface): \(error.localizedDescription)")
      }
    }

    if successCount == 0 {
      throw DNSProxyDaemonError.failedToSetDNS
    }
  }

  func revertDNS() throws {
    logger.info("Restoring system DNS configuration")

    let interfaces = getActiveNetworkInterfaces()
    var successCount = 0

    for interface in interfaces {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
      task.arguments = ["-setdnsservers", interface, "Empty"]

      do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
          successCount += 1
          logger.debug("DNS reverted successfully for interface: \(interface)")
        } else {
          logger.warning("Failed to revert DNS for interface: \(interface)")
        }
      } catch {
        logger.warning("Error reverting DNS for interface \(interface): \(error.localizedDescription)")
      }
    }

    if successCount == 0 {
      throw DNSProxyDaemonError.failedToSetDNS
    }
  }

  func flushCache() throws {
    logger.info("Clearing DNS resolver cache")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
    task.arguments = ["-flushcache"]

    do {
      try task.run()
      task.waitUntilExit()

      let mdnsTask = Process()
      mdnsTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
      mdnsTask.arguments = ["-HUP", "mDNSResponder"]
      try mdnsTask.run()
      mdnsTask.waitUntilExit()

    } catch {
      logger.error("DNS cache flush failed: \(error.localizedDescription)")
      throw DNSProxyDaemonError.failedToFlushCache
    }
  }
}
