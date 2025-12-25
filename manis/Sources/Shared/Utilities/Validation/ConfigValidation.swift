import Foundation
import OSLog
import Rearrange
import SystemPackage
import Yams
import Algorithms

enum ConfigValidationError: MainError {
    case executableNotFound
    case executionFailed(any Error)

    var category: ErrorCategory { .validation }

    static var errorDomain: String { NSError.applicationErrorDomain }

    var errorCode: Int {
        switch self {
        case .executableNotFound: 7001
        case .executionFailed: 7002
        }
    }

    var userFriendlyMessage: String {
        errorDescription ?? "Configuration validation failed"
    }

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Required Mihomo executable is missing from the application bundle"

        case let .executionFailed(error):
            "Configuration validation process failed: \(error.localizedDescription)"
        }
    }

    var failureReason: String? {
        switch self {
        case .executableNotFound:
            "The required executable file is not present in the application bundle"
        case .executionFailed:
            "The validation process encountered an error during execution"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .executableNotFound:
            "Reinstall the application to restore the bundled Mihomo executable."

        case .executionFailed:
            "Verify file permissions and configuration path, then run validation again."
        }
    }

    var recoveryOptions: [String]? {
        switch self {
        case .executableNotFound:
            ["Reinstall App", "Download Manually", "Cancel"]
        case .executionFailed:
            ["Retry", "Check Permissions", "Cancel"]
        }
    }

    var helpAnchor: String? {
        "config-validation-errors"
    }

    var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]
        userInfo[NSLocalizedDescriptionKey] = errorDescription
        userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        userInfo[NSLocalizedRecoveryOptionsErrorKey] = recoveryOptions
        userInfo[NSHelpAnchorErrorKey] = helpAnchor
        userInfo[NSError.errorCategoryKey] = category.stringValue
        userInfo[NSError.userFriendlyMessageKey] = userFriendlyMessage

        if case let .executionFailed(error) = self {
            userInfo[NSUnderlyingErrorKey] = error
        }

        return userInfo
    }
}

enum ValidationResult {
    case success
    case failure(String)

    var isValid: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case let .failure(message) = self {
            return message
        }
        return nil
    }
}

@MainActor
final class ConfigValidation {
    static let shared = ConfigValidation()

    private let logger = MainLog.shared.logger(for: .core)

    private init() {}

    func validate(configPath: String, workingDirectory: String? = nil) async throws
    -> ValidationResult {
        var execPath: String?

        if let bundleURL = Bundle.main.url(forResource: "miho_miho", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let binaryURL = bundle.url(forResource: "manis", withExtension: nil) {
            execPath = binaryURL.path
        } else if let exec = Bundle.main.url(
            forResource: "manis",
            withExtension: nil,
            subdirectory: "Resources",
            ) {
            execPath = exec.path
        }

        guard let exec = execPath else {
            throw ConfigValidationError.executableNotFound
        }

        let workDir = workingDirectory ?? ResourceDomain.shared.configDirectory.path

        guard FileManager.default.fileExists(atPath: configPath) else {
            return .failure("Configuration file not found at the specified path")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exec)
        proc.arguments = ["-t", "-d", workDir, "-f", configPath]
        proc.environment = ["PATH": "/usr/bin:/bin"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        let out =
            String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err =
            String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = out + err

        return proc.terminationStatus == 0 ? .success : .failure(extractErrorMessage(from: combined))
    }

    func validateContent(_ content: String) async throws -> ValidationResult {
        let tmp = FilePath(FileManager.default.temporaryDirectory.appendingPathComponent(
            "cfg_\(UUID().uuidString).yaml",
            ).path)
        defer { try? FileManager.default.removeItem(atPath: tmp.string) }

        let fd = try FileDescriptor.open(tmp, .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o600))
        _ = try fd.closeAfter {
            try fd.writeAll(content.utf8)
        }
        return try await validate(configPath: tmp.string)
    }

    func quickValidate(configPath: String) throws -> ValidationResult {
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return .failure("Unable to read configuration file")
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return .failure("Configuration file is not valid UTF-8")
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure("Configuration file is empty")
        }

        do {
            _ = try YAMLDecoder().decode(ProxyModel.self, from: data)
            return .success
        } catch {
            guard let yaml = try? Yams.load(yaml: content) as? [String: Any] else {
                return .failure("Configuration file is not valid YAML")
            }

            let hasPort = yaml["port"] != nil || yaml["mixed-port"] != nil || yaml["socks-port"] != nil
            let hasProxies = yaml["proxies"] != nil || yaml["proxy-providers"] != nil

            return (hasPort || hasProxies)
                ? .success
                : .failure("Configuration is missing required port or proxy definitions")
        }
    }

    private func extractErrorMessage(from output: String) -> String {
        let lines = output.split(separator: "\n").map(String.init)

        let errorLine = lines.first { line in
            line.contains("level=error") || line.contains("level=fatal")
        }
        .flatMap { line in
            if let msgRange = line.range(of: "msg=") {
                let messageStart = msgRange.upperBound
                let remainingText = String(line[messageStart...])
                return remainingText.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            return nil
        }

        if let error = errorLine {
            return error
        }

        let testFailedLine = lines.first { line in
            line.contains("test failed") || line.lowercased().contains("error:")
        }

        if let testFailed = testFailedLine {
            return testFailed
        }

        return lines.last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Configuration validation failed with an unknown error"
    }

    private func extractLogLevel(from line: String) -> String? {
        let levelPatterns = ["level=error", "level=fatal", "level=warn", "level=info", "level=debug"]

        return levelPatterns.first { pattern in
            line.contains(pattern)
        }
        .flatMap { pattern in
            guard let range = line.range(of: pattern) else { return nil }
            let levelStart = line.index(range.lowerBound, offsetBy: 6)
            let levelEnd = range.upperBound
            return String(line[levelStart ..< levelEnd])
        }
    }

    private func parseStructuredLog(_ line: String) -> (level: String?, message: String?) {
        guard line.contains("level=") else {
            return (nil, nil)
        }

        let level = extractLogLevel(from: line)

        if let msgRange = line.range(of: "msg=") {
            let messageStart = msgRange.upperBound
            let message = String(line[messageStart...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (level, message)
        }

        return (level, nil)
    }
}
