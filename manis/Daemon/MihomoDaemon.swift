import Foundation
import os.log
import Yams

struct InternalMihomoStatus {
    let isRunning: Bool
    let processId: Int32?
    let startTime: Date?
    let configPath: String?
    let externalController: String?
    let secret: String?
    let logs: [String]
}

class MihomoDaemon: @unchecked Sendable {
    private var process: Process?
    private let processQueue = DispatchQueue(label: "com.manis.mihomo.process", qos: .userInitiated)
    private let logsLock = NSLock()
    private var _logs: [String] = []
    private var _startTime: Date?
    private var _configPath: String?
    private var _externalController: String?
    private var _secret: String?

    private var logs: [String] {
        get {
            logsLock.lock()
            defer { logsLock.unlock() }
            return _logs
        }
        set {
            logsLock.lock()
            defer { logsLock.unlock() }
            _logs = newValue
        }
    }

    private var startTime: Date? {
        get {
            logsLock.lock()
            defer { logsLock.unlock() }
            return _startTime
        }
        set {
            logsLock.lock()
            defer { logsLock.unlock() }
            _startTime = newValue
        }
    }

    private var configPath: String? {
        get {
            logsLock.lock()
            defer { logsLock.unlock() }
            return _configPath
        }
        set {
            logsLock.lock()
            defer { logsLock.unlock() }
            _configPath = newValue
        }
    }

    private var externalController: String? {
        get {
            logsLock.lock()
            defer { logsLock.unlock() }
            return _externalController
        }
        set {
            logsLock.lock()
            defer { logsLock.unlock() }
            _externalController = newValue
        }
    }

    private var secret: String? {
        get {
            logsLock.lock()
            defer { logsLock.unlock() }
            return _secret
        }
        set {
            logsLock.lock()
            defer { logsLock.unlock() }
            _secret = newValue
        }
    }

    private let logger = Logger(subsystem: "com.manis.Daemon", category: "MihomoDaemon")

    private let forcedExternalController = "127.0.0.1:9090"

    func start(
        executablePath: String,
        configPath: String,
        configContent: String,
        completion: @escaping @Sendable (Result<String, Error>) -> Void,
    ) {
        processQueue.async { [weak self] in
            guard let self else { return }

            self.stopSync()

            do {
                let generatedSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                var effectiveConfigContent = configContent

                if var config = try? Yams.load(yaml: configContent) as? [String: Any] {
                    config["external-controller"] = self.forcedExternalController
                    config["secret"] = generatedSecret
                    if let dumped = try? Yams.dump(object: config) {
                        effectiveConfigContent = dumped
                    }
                } else {
                    effectiveConfigContent += "\nexternal-controller: \(self.forcedExternalController)\nsecret: \(generatedSecret)\n"
                }

                self.externalController = self.forcedExternalController
                self.secret = generatedSecret

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executablePath)
                proc.currentDirectoryURL = URL(fileURLWithPath: configPath)

                let configFilePath = URL(fileURLWithPath: configPath).appendingPathComponent("config.yaml")
                try effectiveConfigContent.write(to: configFilePath, atomically: true, encoding: .utf8)

                proc.arguments = [
                    "-d", configPath,
                    "-f", configFilePath.path,
                ]

                var environment = ProcessInfo.processInfo.environment
                environment["SAFE_PATHS"] = configPath
                proc.environment = environment

                proc.qualityOfService = .userInitiated

                try proc.run()
                self.process = proc
                self.startTime = Date()
                self.configPath = configPath

                self.logger.info("Mihomo process started with PID: \(proc.processIdentifier)")

                Thread.sleep(forTimeInterval: 2.0)

                if self.testExternalController() {
                    completion(.success("Mihomo started successfully"))
                } else {
                    completion(.failure(MihomoError.apiTestFailed))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func stop(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        processQueue.async { [weak self] in
            guard let self else { return }
            self.stopSync()
            completion(.success(()))
        }
    }

    private func stopSync() {
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
        startTime = nil
        logs = []

        logger.info("Mihomo process stopped")
    }

    func restart(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        processQueue.async { [weak self] in
            guard let self else { return }

            guard let configPath = self.configPath else {
                completion(.failure(MihomoError.noConfigPath))
                return
            }

            let configFilePath = URL(fileURLWithPath: configPath).appendingPathComponent("config.yaml")
            guard let configContent = try? String(contentsOf: configFilePath, encoding: .utf8) else {
                completion(.failure(MihomoError.configReadFailed))
                return
            }

            self.stopSync()

            let executablePath = self.findMihomoExecutable()
            self.start(
                executablePath: executablePath,
                configPath: configPath,
                configContent: configContent,
                completion: completion,
            )
        }
    }

    func getStatus() -> InternalMihomoStatus {
        processQueue.sync {
            InternalMihomoStatus(
                isRunning: process?.isRunning ?? false,
                processId: process?.processIdentifier,
                startTime: startTime,
                configPath: configPath,
                externalController: externalController,
                secret: secret,
                logs: logs,
            )
        }
    }

    private func testExternalController() -> Bool {
        guard let controller = externalController else { return false }

        let proc = Process()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var args = ["http://\(controller)"]
        if let secret, !secret.isEmpty {
            args.append(contentsOf: ["--header", "Authorization: Bearer \(secret)"])
        }

        proc.arguments = args

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hello = response["hello"] as? String,
               hello == "clash.meta" || hello == "mihomo"
            {
                return true
            }
        } catch {
            logger.error("Failed to test external controller: \(error)")
        }

        return false
    }

    private func formatLogMessage(_ message: String) -> String {
        let components = message.split(separator: " ", maxSplits: 2).map(String.init)

        guard components.count == 3,
              components[1].hasPrefix("level="),
              components[2].hasPrefix("msg=")
        else {
            return message
        }

        let level = components[1].replacingOccurrences(of: "level=", with: "")
        var msg = components[2].replacingOccurrences(of: "msg=\"", with: "")

        while msg.last == "\"" || msg.last == "\n" {
            msg.removeLast()
        }

        return "[\(level)] \(msg)"
    }

    private func logCrash(_ terminationStatus: Int32) {
        guard let configPath else { return }

        let logsDir = URL(fileURLWithPath: configPath).appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let crashLog = logs.joined(separator: "\n") + "\nTermination Status: \(terminationStatus)"
        let crashFile = logsDir.appendingPathComponent("mihomo_crash_\(timestamp).log")

        try? crashLog.write(to: crashFile, atomically: true, encoding: .utf8)
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
}

enum MihomoError: Error, LocalizedError {
    case startupFailed(String)
    case startupTimeout
    case apiTestFailed
    case processTerminated(String)
    case noConfigPath
    case configReadFailed

    var errorDescription: String? {
        switch self {
        case let .startupFailed(message):
            "Mihomo startup failed: \(message)"
        case .startupTimeout:
            "Mihomo startup timeout"
        case .apiTestFailed:
            "Failed to connect to Mihomo API"
        case let .processTerminated(message):
            "Mihomo process terminated: \(message)"
        case .noConfigPath:
            "No config path available"
        case .configReadFailed:
            "Failed to read config file"
        }
    }
}
