import ConcurrencyExtras
import Foundation
import OSLog
import SwiftyXPC
@preconcurrency import XPC

final class XPCBridge: @unchecked Sendable {
    private let daemonService: DaemonService
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "XPCListener")
    private let shouldQuit = LockIsolated(false)
    private let listener: SwiftyXPC.XPCListener

    init(daemonService: DaemonService) throws {
        self.daemonService = daemonService
        self.listener = try SwiftyXPC.XPCListener(type: .machService(name: "com.manis.Daemon"), codeSigningRequirement: nil)
        setupMessageHandlers()
    }

    private func setupMessageHandlers() {
        listener.setMessageHandler(name: "handleRequest") { [weak self] (_: SwiftyXPC.XPCConnection, request: DaemonRequest) async throws -> DaemonResponse in
            guard let self else {
                throw DaemonError.serviceUnavailable("Service unavailable")
            }

            return await self.daemonService.handleRequest(request)
        }

        listener.errorHandler = { [weak self] (_: SwiftyXPC.XPCConnection, error: Error) in
            self?.logger.error("XPC connection error: \(error)")
        }
    }

    func start() async throws {
        listener.activate()
        logger.info("XPC Daemon listener activated")
        await runEventLoop()
    }

    private func runEventLoop() async {
        logger.info("Starting daemon event loop")

        while !shouldQuit.value {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        logger.info("Daemon event loop ended")
    }
}
