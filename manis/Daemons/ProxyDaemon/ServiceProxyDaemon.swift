import AppKit
import Foundation
import OSLog
import SystemConfiguration

final class ServiceProxyDaemon: NSObject, ProtocolProxyDaemon, NSXPCListenerDelegate {
  private let listener: NSXPCListener
  private var connections = [NSXPCConnection]()
  private let logger = Logger(subsystem: "com.sonqyau.manis.daemon", category: "service")

  private var mihomoTask: Process?
  private let allowedBundleIdentifier = "com.sonqyau.manis"

  override init() {
    listener = NSXPCListener(machServiceName: "com.sonqyau.manis.daemon")
    super.init()
    listener.delegate = self
  }

  func run() {
    listener.resume()
    logger.info("Proxy daemon listener started")
    RunLoop.current.run()
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection)
    -> Bool
  {
    guard isValidConnection(newConnection) else {
      logger.error("Rejected connection from unauthorized client process")
      return false
    }

    newConnection.exportedInterface = NSXPCInterface(with: (any ProtocolProxyDaemon).self)
    newConnection.exportedObject = self

    newConnection.invalidationHandler = { [weak self] in
      guard let self = self,
        let index = self.connections.firstIndex(of: newConnection)
      else { return }
      self.connections.remove(at: index)
      self.logger.debug("Client connection invalidated; remaining connections: \(self.connections.count)")
    }

    self.connections.append(newConnection)
    newConnection.resume()
    logger.debug("Accepted client connection; active connections: \(self.connections.count)")

    return true
  }

  private func isValidConnection(_ connection: NSXPCConnection) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier),
      let bundleIdentifier = app.bundleIdentifier
    else {
      return false
    }
    return bundleIdentifier == allowedBundleIdentifier
  }

  func getVersion(reply: @escaping @Sendable (String) -> Void) {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    reply(version)
  }

  nonisolated func enableProxy(
    port: Int, socksPort: Int, pac: String?, filterInterface: Bool, ignoreList: [String],
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Enabling system proxy: HTTP(S)=\(port), SOCKS=\(socksPort)")
    Task.detached { @MainActor in
      do {
        try SystemProxyDaemon.shared.enableProxy(
          httpPort: port,
          socksPort: socksPort,
          pacURL: pac,
          filterInterface: filterInterface,
          ignoreList: ignoreList
        )
        reply(nil)
      } catch {
        log.error("Failed to enable proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func disableProxy(
    filterInterface: Bool, reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Disabling system proxy")
    Task.detached { @MainActor in
      do {
        try SystemProxyDaemon.shared.disableProxy(filterInterface: filterInterface)
        reply(nil)
      } catch {
        log.error("Failed to disable proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func restoreProxy(
    currentPort: Int, socksPort: Int, info: [String: Any], filterInterface: Bool,
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Restoring system proxy configuration")
    nonisolated(unsafe) let proxyInfo = info
    Task { @MainActor in
      do {
        try SystemProxyDaemon.shared.restoreProxy(
          currentPort: currentPort,
          socksPort: socksPort,
          info: proxyInfo,
          filterInterface: filterInterface
        )
        reply(nil)
      } catch {
        log.error("Failed to restore proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func getCurrentProxySetting(reply: @escaping @Sendable ([String: Any]) -> Void) {
    Task { @MainActor in
      let settings = SystemProxyDaemon.shared.getCurrentProxySettings()
      reply(settings)
    }
  }

  nonisolated func startMihomo(
    path: String, confPath: String, confFilePath: String, confJSON: String,
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Starting Mihomo core process")
    Task { @MainActor in
      do {
        try MihomoProxyDaemon.shared.start(
          executablePath: path,
          configPath: confPath,
          configFilePath: confFilePath,
          configJSON: confJSON
        )
        reply(nil)
      } catch {
        log.error("Failed to start Mihomo: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func stopMihomo(reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Stopping Mihomo core process")
    Task { @MainActor in
      MihomoProxyDaemon.shared.stop()
      reply(nil)
    }
  }

  nonisolated func getUsedPorts(reply: @escaping @Sendable (String?) -> Void) {
    Task { @MainActor in
      let ports = MihomoProxyDaemon.shared.getUsedPorts()
      reply(ports)
    }
  }

  nonisolated func updateTun(
    state: Bool, dns: String, reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Updating TUN state=\(state) dnsServer=\(dns)")
    Task { @MainActor in
      do {
        try DNSProxyDaemon.shared.updateTun(enabled: state, dnsServer: dns)
        reply(nil)
      } catch {
        log.error("Failed to update TUN: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func flushDnsCache(reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Clearing DNS resolver cache")
    Task { @MainActor in
      do {
        try DNSProxyDaemon.shared.flushCache()
        reply(nil)
      } catch {
        log.error("Failed to flush DNS cache: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func enableTUNMode(dnsServer: String, reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Enabling TUN mode with DNS server: \(dnsServer)")
    Task { @MainActor in
      do {
        try TUNProxyDaemon.shared.enableTUN(dnsServer: dnsServer)
        reply(nil)
      } catch {
        log.error("Failed to enable TUN mode: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func disableTUNMode(reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Disabling TUN mode")
    Task { @MainActor in
      do {
        try TUNProxyDaemon.shared.disableTUN()
        reply(nil)
      } catch {
        log.error("Failed to disable TUN mode: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func getTUNStatus(reply: @escaping @Sendable ([String: Any]) -> Void) {
    Task { @MainActor in
      let status = TUNProxyDaemon.shared.getStatus()
      reply(status)
    }
  }

  nonisolated func validateKernelBinary(path: String, reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Validating kernel binary at path: \(path)")
    Task { @MainActor in
      do {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
          throw NSError(domain: "com.sonqyau.manis.daemon", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Kernel binary not found at path: \(path)"
          ])
        }
        
        guard fileManager.isExecutableFile(atPath: path) else {
          throw NSError(domain: "com.sonqyau.manis.daemon", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "Kernel binary is not executable: \(path)"
          ])
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-v"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
          log.info("Kernel binary validation successful")
          reply(nil)
        } else {
          throw NSError(domain: "com.sonqyau.manis.daemon", code: -3, userInfo: [
            NSLocalizedDescriptionKey: "Kernel binary failed validation test"
          ])
        }
      } catch {
        log.error("Kernel binary validation failed: \(error.localizedDescription)")
        reply(error)
      }
    }
  }
}
