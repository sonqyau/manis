import ConcurrencyExtras
import Foundation
import OSLog
@preconcurrency import XPC

final class XPCBridge: @unchecked Sendable {
    private let daemonService: DaemonService
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "XPCListener")
    private let shouldQuit = LockIsolated(false)

    init(daemonService: DaemonService) {
        self.daemonService = daemonService
    }

    func start() async throws {
        let listener = try createListener()

        do {
            try listener.activate()
            logger.info("XPC Daemon listener activated")
        } catch {
            logger.error("Failed to activate XPC listener: \(error)")
            throw error
        }

        await runEventLoop()
    }

    private func createListener() throws -> XPCListener {
        try XPCListener(
            service: "com.manis.Daemon",
            targetQueue: nil,
            options: [],
            ) { [weak self] request in
            guard let self else {
                return request.reject(reason: "Service unavailable")
            }

            let (decision, _) = request.accept(
                incomingMessageHandler: { @Sendable receivedMessage in
                    Task { @Sendable in
                        let response = await self.handleMessage(receivedMessage)
                        receivedMessage.reply(response)
                    }
                    return nil
                },
                cancellationHandler: { [weak self] _ in
                    self?.shouldQuit.setValue(true)
                    self?.logger.info("XPC connection cancelled, shutting down")
                },
                )
            return decision
        }
    }

    private func handleMessage(_ receivedMessage: XPCReceivedMessage) async -> DaemonResponse {
        do {
            let request = try receivedMessage.decode(as: DaemonRequest.self)
            logger.debug("Received XPC request: \(request.method)")

            let response = await daemonService.handleRequest(request)
            logger.debug("Sending XPC response for: \(request.method)")

            return response
        } catch {
            logger.error("Failed to handle XPC message: \(error)")
            return .error(MainXPCError(error: error))
        }
    }

    private func runEventLoop() async {
        logger.info("Starting daemon event loop")

        while !shouldQuit.value {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        logger.info("Daemon event loop ended")
    }
}
