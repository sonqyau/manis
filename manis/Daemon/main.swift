import ConcurrencyExtras
import Foundation
import OSLog
import SystemPackage
import XPC

Foundation.ProcessInfo.processInfo.disableSuddenTermination()

let logger = Logger(subsystem: "com.manis.Daemon", category: "Main")

logger.info("Starting MainDaemon")

let daemonService = DaemonService()
let xpcListener = XPCBridge(daemonService: daemonService)

do {
    try await xpcListener.start()
} catch let errno as Errno {
    logger.error("Failed to start daemon: \(errno)")
    exit(1)
} catch {
    logger.error("Failed to start daemon: \(error)")
    exit(1)
}
