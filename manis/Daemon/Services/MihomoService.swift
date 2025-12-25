import AsyncAlgorithms
import AsyncQueue
import ConcurrencyExtras
import Foundation
import OSLog
import SystemPackage
import Yams

actor MihomoService {
    private var state: MihomoState = .stopped
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "MihomoService")

    private var process: Process?
    private let queue = ActorQueue<MihomoService>()

    private let forcedExternalController = "127.0.0.1:9090"

    init() {
        queue.adoptExecutionContext(of: self)
    }

    func start(executablePath: String, configPath: String, configContent: String) async throws -> String {
        guard case .stopped = state else {
            throw DaemonError.invalidStateTransition(
                from: String(describing: state),
                to: "starting",
                )
        }

        state = .starting
        logger.info("Starting Mihomo process")

        return try await withCheckedThrowingContinuation { continuation in
            Task(on: queue) { myself in
                do {
                    let result = try await myself.startProcess(
                        executablePath: executablePath,
                        configPath: configPath,
                        configContent: configContent,
                        )
                    continuation.resume(returning: result)
                } catch {
                    await myself.handleError(error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async throws {
        guard case .running = state else {
            logger.info("Mihomo already stopped")
            return
        }

        state = .stopping
        logger.info("Stopping Mihomo process")

        return try await withCheckedThrowingContinuation { continuation in
            Task(on: queue) { myself in
                do {
                    try await myself.stopProcess()
                    continuation.resume()
                } catch {
                    await myself.handleError(error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func restart() async throws -> String {
        logger.info("Restarting Mihomo process")

        guard case let .running(processInfo) = state else {
            throw DaemonError.invalidStateTransition(
                from: String(describing: state),
                to: "restarting",
                )
        }

        let configPath = processInfo.configPath
        let configFilePath = URL(fileURLWithPath: configPath).appendingPathComponent("config.yaml")

        guard let configContent = try? String(contentsOf: configFilePath, encoding: .utf8) else {
            throw DaemonError.configurationError("Failed to read config file for restart")
        }

        try await stop()

        let executablePath = findMihomoExecutable()
        return try await start(
            executablePath: executablePath,
            configPath: configPath,
            configContent: configContent,
            )
    }

    func getStatus() async -> MihomoStatus {
        switch state {
        case .stopped:
            MihomoStatus(
                isRunning: false,
                processId: 0,
                startTime: nil,
                configPath: nil,
                externalController: nil,
                secret: nil,
                logs: [],
                )

        case .starting:
            MihomoStatus(
                isRunning: false,
                processId: 0,
                startTime: nil,
                configPath: nil,
                externalController: nil,
                secret: nil,
                logs: ["Starting..."],
                )

        case let .running(processInfo):
            MihomoStatus(
                isRunning: true,
                processId: processInfo.pid,
                startTime: processInfo.startTime,
                configPath: processInfo.configPath,
                externalController: processInfo.externalController,
                secret: processInfo.secret,
                logs: [],
                )

        case .stopping:
            MihomoStatus(
                isRunning: false,
                processId: 0,
                startTime: nil,
                configPath: nil,
                externalController: nil,
                secret: nil,
                logs: ["Stopping..."],
                )

        case let .error(error):
            MihomoStatus(
                isRunning: false,
                processId: 0,
                startTime: nil,
                configPath: nil,
                externalController: nil,
                secret: nil,
                logs: ["Error: \(error.localizedDescription)"],
                )
        }
    }

    private func startProcess(executablePath: String, configPath: String, configContent: String) async throws -> String {
        await stopProcessSync()

        let generatedSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let effectiveConfigContent = try prepareConfig(configContent, secret: generatedSecret)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.currentDirectoryURL = URL(fileURLWithPath: configPath)

        let configFilePath = FilePath(URL(fileURLWithPath: configPath).appendingPathComponent("config.yaml").path)
        let fd = try FileDescriptor.open(configFilePath, .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644))
        _ = try fd.closeAfter {
            try fd.writeAll(effectiveConfigContent.utf8)
        }

        proc.arguments = [
            "-d", configPath,
            "-f", configFilePath.string,
        ]

        var environment = Foundation.ProcessInfo.processInfo.environment
        environment["SAFE_PATHS"] = configPath
        proc.environment = environment
        proc.qualityOfService = .userInitiated

        try proc.run()
        self.process = proc

        let processInfo = ProcessInfo(
            pid: proc.processIdentifier,
            startTime: Date(),
            configPath: configPath,
            externalController: forcedExternalController,
            secret: generatedSecret,
            )

        state = .running(processInfo)
        logger.info("Mihomo process started with PID: \(proc.processIdentifier)")

        try await Task.sleep(nanoseconds: 2_000_000_000)

        if await testExternalController(secret: generatedSecret) {
            return "Mihomo started successfully"
        } else {
            throw DaemonError.processError("Failed to connect to Mihomo API")
        }
    }

    private func stopProcess() async throws {
        await stopProcessSync()
        state = .stopped
        logger.info("Mihomo process stopped")
    }

    private func stopProcessSync() async {
        guard let proc = process, proc.isRunning else {
            return
        }

        proc.terminate()
        proc.waitUntilExit()

        if proc.isRunning {
            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
            killProc.arguments = ["-9", "\(proc.processIdentifier)"]
            try? killProc.run()
            killProc.waitUntilExit()
        }

        process = nil
    }

    private func prepareConfig(_ configContent: String, secret: String) throws -> String {
        var effectiveConfigContent = configContent

        if var config = try? Yams.load(yaml: configContent) as? [String: Any] {
            config["external-controller"] = forcedExternalController
            config["secret"] = secret
            if let dumped = try? Yams.dump(object: config) {
                effectiveConfigContent = dumped
            }
        } else {
            effectiveConfigContent += "\nexternal-controller: \(forcedExternalController)\nsecret: \(secret)\n"
        }

        return effectiveConfigContent
    }

    private func testExternalController(secret: String) async -> Bool {
        let proc = Process()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var args = ["http://\(forcedExternalController)"]
        if !secret.isEmpty {
            args.append(contentsOf: ["--header", "Authorization: Bearer \(secret)"])
        }

        proc.arguments = args

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hello = response["hello"] as? String,
               hello == "clash.meta" || hello == "mihomo" {
                return true
            }
        } catch {
            logger.error("Failed to test external controller: \(error)")
        }

        return false
    }

    private func startProcessWithRetry(
        executablePath: String,
        configPath: String,
        configContent: String,
        secret: String
    ) async throws -> String {
        let maxRetries = 3
        let retryDelay = Duration.seconds(2)

        let retryStream = AsyncTimerSequence(interval: retryDelay, clock: ContinuousClock())
            .compactMap { _ in }
            .debounce(for: .milliseconds(100))

        var attempt = 0

        for await _ in retryStream {
            attempt += 1
            do {
                let result = try await startProcess(
                    executablePath: executablePath,
                    configPath: configPath,
                    configContent: configContent
                )
                return result
            } catch {
                logger.warning("Process start attempt \(attempt) failed: \(error)")
                if attempt >= maxRetries {
                    throw error
                }
            }
        }

        throw DaemonError.processError("Failed to start process after \(maxRetries) attempts")
    }

    private func findMihomoExecutable() -> String {
        let possiblePaths = [
            "/usr/local/bin/mihomo",
            "/opt/homebrew/bin/mihomo",
            "/usr/bin/mihomo",
        ]

        for path in possiblePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return "mihomo"
    }

    private func handleError(_ error: Error) async {
        logger.error("Mihomo service error: \(error.localizedDescription)")
        state = .error(error)
    }
}
