import Foundation
import OSLog
@preconcurrency import XPC

final class XPCConnection: @unchecked Sendable {
    private let xpcService: XPCService
    private let logger = Logger(subsystem: "com.manis.XPC", category: "XPCConnection")
    private var shouldQuit = false
    private let shouldQuitLock = NSLock()

    init(xpcService: XPCService) {
        self.xpcService = xpcService
    }

    private var shouldQuitValue: Bool {
        shouldQuitLock.lock()
        defer { shouldQuitLock.unlock() }
        return shouldQuit
    }

    private func setShouldQuit(_ value: Bool) {
        shouldQuitLock.lock()
        defer { shouldQuitLock.unlock() }
        shouldQuit = value
    }

    func start() async throws {
        let listener = try createListener()

        do {
            try listener.activate()
            logger.info("XPC Service listener activated")
        } catch {
            logger.error("Failed to activate XPC listener: \(error)")
            throw error
        }

        await runEventLoop()
    }

    private func createListener() throws -> XPCListener {
        try XPCListener(
            service: "com.manis.XPC",
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
                    self?.setShouldQuit(true)
                    self?.logger.info("XPC connection cancelled, shutting down")
                },
            )
            return decision
        }
    }

    private func handleMessage(_ receivedMessage: XPCReceivedMessage) async -> XPCResponse {
        do {
            let request = try receivedMessage.decode(as: XPCRequest.self)
            logger.debug("Received XPC request: \(request.method)")

            let response = await xpcService.handleRequest(request)
            logger.debug("Sending XPC response for: \(request.method)")

            return response
        } catch {
            logger.error("Failed to handle XPC message: \(error)")
            return .error(MainXPCError(error: error))
        }
    }

    private func runEventLoop() async {
        logger.info("Starting XPC service event loop")

        while !shouldQuitValue {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        logger.info("XPC service event loop ended")
    }
}
