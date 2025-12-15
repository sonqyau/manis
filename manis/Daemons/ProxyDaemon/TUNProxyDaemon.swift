import Foundation
import OSLog
import Network

enum TUNProxyDaemonError: Error, LocalizedError {
  case failedToCreateTUN
  case failedToConfigureRouting
  case failedToSetupPF
  case insufficientPrivileges
  case tunNotSupported

  var userFriendlyMessage: String {
    errorDescription ?? "TUN configuration error"
  }

  var errorDescription: String? {
    switch self {
    case .failedToCreateTUN:
      "Unable to create TUN device. This requires administrator privileges."
    case .failedToConfigureRouting:
      "Unable to configure routing table. Administrator privileges required."
    case .failedToSetupPF:
      "Unable to configure packet filter rules. Administrator privileges required."
    case .insufficientPrivileges:
      "Insufficient privileges for TUN operations. Run as administrator."
    case .tunNotSupported:
      "TUN device not supported on this system."
    }
  }
}

@MainActor
final class TUNProxyDaemon {
  static let shared = TUNProxyDaemon()
  
  private let logger = Logger(subsystem: "com.sonqyau.manis.daemon", category: "tun")
  private var tunInterface: String?
  private var isActive = false
  
  private init() {}
  
  func enableTUN(dnsServer: String = "127.0.0.1") throws {
    logger.info("Attempting to enable TUN mode")
    
    guard getuid() == 0 else {
      logger.error("TUN mode requires root privileges")
      throw TUNProxyDaemonError.insufficientPrivileges
    }
    
    do {
      try createUTUNInterface()
      try configureRouting()
      try setupPacketFilter()
      
      isActive = true
      logger.info("TUN mode enabled successfully")
      
    } catch {
      logger.error("Failed to enable TUN mode: \(error.localizedDescription)")
      try? disableTUN()
      throw error
    }
  }
  
  func disableTUN() throws {
    logger.info("Disabling TUN mode")
    
    do {
      try cleanupPacketFilter()
      try cleanupRouting()
      try destroyUTUNInterface()
      
      isActive = false
      logger.info("TUN mode disabled successfully")
      
    } catch {
      logger.error("Error during TUN cleanup: \(error.localizedDescription)")
      throw error
    }
  }
  
  private func createUTUNInterface() throws {
    logger.debug("Creating UTUN interface")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    
    for i in 0..<10 {
      let interfaceName = "utun\(i)"
      task.arguments = [interfaceName, "create"]
      
      do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
          tunInterface = interfaceName
          logger.debug("Created UTUN interface: \(interfaceName)")
          return
        }
      } catch {
        continue
      }
    }
    
    throw TUNProxyDaemonError.failedToCreateTUN
  }
  
  private func destroyUTUNInterface() throws {
    guard let interface = tunInterface else { return }
    
    logger.debug("Destroying UTUN interface: \(interface)")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    task.arguments = [interface, "destroy"]
    
    do {
      try task.run()
      task.waitUntilExit()
      
      if task.terminationStatus == 0 {
        tunInterface = nil
        logger.debug("UTUN interface destroyed")
      }
    } catch {
      logger.warning("Failed to destroy UTUN interface: \(error.localizedDescription)")
    }
  }
  
  private func configureRouting() throws {
    guard let interface = tunInterface else {
      throw TUNProxyDaemonError.failedToCreateTUN
    }
    
    logger.debug("Configuring routing for interface: \(interface)")
    
    let configTask = Process()
    configTask.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    configTask.arguments = [interface, "inet", "198.18.0.1", "198.18.0.2", "up"]
    
    do {
      try configTask.run()
      configTask.waitUntilExit()
      
      if configTask.terminationStatus != 0 {
        throw TUNProxyDaemonError.failedToConfigureRouting
      }
    } catch {
      throw TUNProxyDaemonError.failedToConfigureRouting
    }
    
    let routeTask = Process()
    routeTask.executableURL = URL(fileURLWithPath: "/sbin/route")
    routeTask.arguments = ["-n", "add", "-net", "0.0.0.0/1", "-interface", interface]
    
    do {
      try routeTask.run()
      routeTask.waitUntilExit()
    } catch {
      logger.warning("Failed to add route: \(error.localizedDescription)")
    }
  }
  
  private func cleanupRouting() throws {
    guard let interface = tunInterface else { return }
    
    logger.debug("Cleaning up routing for interface: \(interface)")
    
    let routeTask = Process()
    routeTask.executableURL = URL(fileURLWithPath: "/sbin/route")
    routeTask.arguments = ["-n", "delete", "-net", "0.0.0.0/1", "-interface", interface]
    
    do {
      try routeTask.run()
      routeTask.waitUntilExit()
    } catch {
      logger.debug("Route cleanup completed (may have been already removed)")
    }
  }
  
  private func setupPacketFilter() throws {
    logger.debug("Setting up packet filter rules")
    
    let pfRules = """
    nat on en0 from 198.18.0.0/16 to any -> (en0)
    pass out on utun+ all
    pass in on utun+ all
    """
    
    let tempFile = "/tmp/manis_pf_rules"
    try pfRules.write(toFile: tempFile, atomically: true, encoding: .utf8)
    
    let pfTask = Process()
    pfTask.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
    pfTask.arguments = ["-f", tempFile]
    
    do {
      try pfTask.run()
      pfTask.waitUntilExit()
      
      if pfTask.terminationStatus != 0 {
        throw TUNProxyDaemonError.failedToSetupPF
      }
    } catch {
      throw TUNProxyDaemonError.failedToSetupPF
    }
    
    let enableTask = Process()
    enableTask.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
    enableTask.arguments = ["-e"]
    
    do {
      try enableTask.run()
      enableTask.waitUntilExit()
    } catch {
      logger.warning("PF may already be enabled")
    }
    
    try? FileManager.default.removeItem(atPath: tempFile)
  }
  
  private func cleanupPacketFilter() throws {
    logger.debug("Cleaning up packet filter rules")
    
    let flushTask = Process()
    flushTask.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
    flushTask.arguments = ["-F", "all"]
    
    do {
      try flushTask.run()
      flushTask.waitUntilExit()
    } catch {
      logger.debug("PF cleanup completed")
    }
  }
  
  func getStatus() -> [String: Any] {
    return [
      "active": isActive,
      "interface": tunInterface ?? "none",
      "method": "utun"
    ]
  }
}