import ConcurrencyExtras
import Foundation
import OSLog
import XPC

Foundation.ProcessInfo.processInfo.disableSuddenTermination()

let logger = Logger(subsystem: "com.manis.Daemon", category: "Main")

logger.info("Starting MainDaemon")

let daemonService = DaemonService()
let xpcListener = XPCBridge(daemonService: daemonService)

do {
    try await xpcListener.start()
} catch {
    logger.error("Failed to start daemon: \(error)")
    exit(1)
}
