import Foundation
import OSLog

let logger = Logger(subsystem: "com.manis.XPC", category: "Main")

logger.info("Starting MainXPC")

let xpcService = XPCService()
let xpcListener = XPCConnection(xpcService: xpcService)

do {
    try await xpcListener.start()
} catch {
    logger.error("Failed to start XPC service: \(error)")
    exit(1)
}
