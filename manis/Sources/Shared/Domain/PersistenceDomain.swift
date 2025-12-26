import Clocks
@preconcurrency import Combine
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import OSLog
import SwiftData
import SystemPackage
import UserNotifications

@MainActor
@Observable
final class PersistenceDomain {
    static let shared = PersistenceDomain()

    struct State {
        var configs: [PersistenceModel]
        var remoteInstances: [RemoteInstance]
        var isLocalMode: Bool
        var activeRemoteInstance: RemoteInstance?
    }

    private let logger = MainLog.shared.logger(for: .core)
    private let resourceManager = ResourceDomain.shared
    private let apiClient = MihomoDomain()
    private let clock: any Clock<Duration>

    private let stateSubject: CurrentValueSubject<State, Never>

    private(set) var modelContainer: ModelContainer?
    private(set) var configs: [PersistenceModel] = [] {
        didSet { emitState() }
    }

    private(set) var remoteInstances: [RemoteInstance] = [] {
        didSet { emitState() }
    }

    private var autoUpdateTask: Task<Void, Never>?
    private let defaultUpdateInterval: TimeInterval = 7200

    var isLocalMode: Bool {
        guard let container = modelContainer else { return true }
        let context = container.mainContext
        let activeInstanceDescriptor = FetchDescriptor<RemoteInstance>(
            predicate: #Predicate<RemoteInstance> { $0.isActive == true },
            )
        let activeInstances = try? context.fetch(activeInstanceDescriptor)
        return activeInstances?.isEmpty ?? true
    }

    var activeRemoteInstance: RemoteInstance? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        let activeInstanceDescriptor = FetchDescriptor<RemoteInstance>(
            predicate: #Predicate<RemoteInstance> { $0.isActive == true },
            )
        return try? context.fetch(activeInstanceDescriptor).first
    }

    private init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        stateSubject = CurrentValueSubject(
            State(
                configs: [],
                remoteInstances: [],
                isLocalMode: true,
                activeRemoteInstance: nil,
                ),
            )
    }

    func statePublisher() -> AnyPublisher<State, Never> {
        stateSubject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private var state: State {
        State(
            configs: configs,
            remoteInstances: remoteInstances,
            isLocalMode: isLocalMode,
            activeRemoteInstance: activeRemoteInstance,
            )
    }

    private func emitState() {
        stateSubject.send(state)
    }

    private func mapError(_ error: any Error) -> PersistenceError {
        if let remoteError = error as? PersistenceError {
            return remoteError
        }
        return .validationFailed(error.applicationMessage)
    }

    private func performDatabase<T>(_ operation: () throws -> T) throws(PersistenceError) -> T {
        do {
            return try operation()
        } catch {
            throw mapError(error)
        }
    }

    func initialize(container: ModelContainer) throws(PersistenceError) {
        modelContainer = container
        try loadConfigs()
        try loadRemoteInstances()
        setupAutoUpdate()
    }

    private func loadConfigs() throws(PersistenceError) {
        guard let container = modelContainer else {
            throw PersistenceError.notInitialized
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<PersistenceModel>(
            sortBy: [SortDescriptor(\.createdAt)],
            )

        do {
            configs = try performDatabase {
                try context.fetch(descriptor)
            }
            logger.info("Loaded \(configs.count) remote configurations.")
        } catch {
            throw mapError(error)
        }
    }

    private func loadRemoteInstances() throws(PersistenceError) {
        guard let container = modelContainer else {
            throw PersistenceError.notInitialized
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<RemoteInstance>(
            sortBy: [SortDescriptor(\.createdAt)],
            )

        do {
            let instances = try performDatabase {
                try context.fetch(descriptor)
            }
            remoteInstances = instances
            try performDatabase {
                try context.save()
            }
            logger.info("Loaded \(remoteInstances.count) remote instances")
        } catch {
            throw mapError(error)
        }
    }

    func addConfig(name: String, url: String) async throws(PersistenceError) {
        guard let container = modelContainer else { throw PersistenceError.notInitialized }
        guard URL(string: url) != nil else { throw PersistenceError.invalidURL }

        let context = container.mainContext
        let duplicateDescriptor = FetchDescriptor<PersistenceModel>(
            predicate: #Predicate<PersistenceModel> { $0.url == url },
            )
        let existingConfigs = try performDatabase {
            try context.fetch(duplicateDescriptor)
        }
        guard existingConfigs.isEmpty else { throw PersistenceError.duplicateURL }

        do {
            let cfg = PersistenceModel(name: name, url: url)
            container.mainContext.insert(cfg)

            try container.mainContext.save()
            try loadConfigs()

            try await updateConfig(cfg)
        } catch {
            throw mapError(error)
        }
    }

    func removeConfig(_ config: PersistenceModel) throws(PersistenceError) {
        guard let container = modelContainer else {
            throw PersistenceError.notInitialized
        }

        let context = container.mainContext
        context.delete(config)

        do {
            try context.save()
            try loadConfigs()

            logger.info("Removed remote configuration: \(config.name).")
        } catch {
            throw mapError(error)
        }
    }

    func updateConfig(_ config: PersistenceModel) async throws(PersistenceError) {
        guard let url = URL(string: config.url) else { throw PersistenceError.invalidURL }

        var request = HTTPRequest(method: .get, url: url)
        request.headerFields[.userAgent] = "manis/1.0"

        guard let urlRequest = URLRequest(httpRequest: request) else {
            throw PersistenceError.downloadFailed
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = resp as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                throw PersistenceError.downloadFailed
            }

            guard let content = String(data: data, encoding: .utf8) else {
                throw PersistenceError.invalidEncoding
            }

            let result = try await ConfigValidation.shared.validateContent(content)
            guard result.isValid else {
                throw PersistenceError.validationFailed(result.errorMessage ?? "Invalid configuration.")
            }

            let path = FilePath(resourceManager.configDirectory.appendingPathComponent("\(config.name).yaml").path)
            let fd = try FileDescriptor.open(path, .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644))
            _ = try fd.closeAfter {
                try fd.writeAll(content.utf8)
            }

            config.lastUpdated = Date()
            config.updatedAt = Date()

            try modelContainer?.mainContext.save()

            if config.isActive {
                try await reloadActiveConfig()
            }

            emitState()
        } catch {
            throw mapError(error)
        }
    }

    func activateConfig(_ config: PersistenceModel) async throws(PersistenceError) {
        guard let container = modelContainer else { throw PersistenceError.notInitialized }
        let context = container.mainContext

        let deactivateDescriptor = FetchDescriptor<PersistenceModel>(
            predicate: #Predicate<PersistenceModel> { $0.isActive == true },
            )
        let activeConfigs = try performDatabase {
            try context.fetch(deactivateDescriptor)
        }
        for activeConfig in activeConfigs {
            activeConfig.isActive = false
        }

        config.isActive = true

        do {
            try modelContainer?.mainContext.save()

            let src = FilePath(resourceManager.configDirectory.appendingPathComponent("\(config.name).yaml").path)
            let dst = FilePath(resourceManager.configFilePath.path)

            guard FileManager.default.fileExists(atPath: src.string) else {
                throw PersistenceError.validationFailed("Source configuration not found.")
            }

            try backupConfig()

            if FileManager.default.fileExists(atPath: dst.string) {
                try FileManager.default.removeItem(atPath: dst.string)
            }

            try FileManager.default.copyItem(atPath: src.string, toPath: dst.string)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.string)
            try await reloadActiveConfig()

            emitState()
        } catch {
            throw mapError(error)
        }
    }

    func validateConfig(at path: String) async throws(PersistenceError) {
        do {
            let result = try await ConfigValidation.shared.validate(configPath: path)
            guard result.isValid else {
                throw PersistenceError.validationFailed(
                    result.errorMessage ?? "Configuration validation failed.",
                    )
            }
        } catch {
            throw mapError(error)
        }
    }

    private func reloadActiveConfig() async throws {
        try await apiClient.reloadConfig(
            path: resourceManager.configFilePath.path,
            payload: "",
            )
    }

    func backupConfig() throws(PersistenceError) {
        let path = FilePath(resourceManager.configFilePath.path)
        guard FileManager.default.fileExists(atPath: path.string) else {
            return
        }

        do {
            let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = resourceManager.configDirectory
                .appendingPathComponent("config_bak_\(ts).yaml")

            try FileManager.default.copyItem(atPath: path.string, toPath: backup.path)
            try cleanupOldBackups()
        } catch {
            throw mapError(error)
        }
    }

    private func cleanupOldBackups() throws(PersistenceError) {
        do {
            let backups = try FileManager.default.contentsOfDirectory(
                at: resourceManager.configDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles],
                )
            .filter { $0.lastPathComponent.hasPrefix("config_bak_") }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                return d1 > d2
            }

            for old in backups.dropFirst(10) {
                try FileManager.default.removeItem(at: old)
            }
        } catch {
            throw mapError(error)
        }
    }

    private func setupAutoUpdate() {
        autoUpdateTask?.cancel()
        autoUpdateTask = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(defaultUpdateInterval))
                guard !Task.isCancelled else { break }
                await performAutoUpdate()
            }
        }
    }

    private func performAutoUpdate() async {
        guard let container = modelContainer else { return }
        let context = container.mainContext

        let autoUpdateDescriptor = FetchDescriptor<PersistenceModel>(
            predicate: #Predicate<PersistenceModel> { $0.autoUpdate == true },
            )

        do {
            let autoUpdateConfigs = try performDatabase {
                try context.fetch(autoUpdateDescriptor)
            }
            for cfg in autoUpdateConfigs {
                do {
                    try await updateConfig(cfg)
                    if cfg.isActive {
                        await sendNotification(
                            title: "Configuration updated",
                            body: "\(cfg.name) was updated successfully.",
                            )
                    }
                } catch {
                    let chain = error.errorChainDescription
                    logger.error(
                        "Configuration update failed for \(cfg.name): \(error.localizedDescription)\n\(chain)",
                        )
                    if cfg.isActive {
                        await sendNotification(
                            title: "Configuration update failed",
                            body: "\(cfg.name): \(error.localizedDescription)",
                            )
                    }
                }
            }
        } catch {
            logger.error("Auto-update configuration fetch failed: \(error.localizedDescription)")
        }
    }

    func updateAllConfigs() async {
        for config in configs {
            do {
                try await updateConfig(config)
            } catch {
                let chain = error.errorChainDescription
                logger.error(
                    "Configuration update failed for \(config.name): \(error.localizedDescription)\n\(chain)",
                    )
            }
        }

        emitState()
    }

    func addRemoteInstance(name: String, apiURL: String, secret: String?) throws(PersistenceError) {
        guard let container = modelContainer else {
            throw PersistenceError.notInitialized
        }

        let sanitizedName: String
        let sanitizedURL: String
        let sanitizedSecret: String?

        do {
            sanitizedName = try InputValidation.sanitizedIdentifier(name, fieldName: "instance name")
            sanitizedURL = try InputValidation.sanitizedURLString(apiURL)
            sanitizedSecret = try InputValidation.sanitizedSecret(secret)
        } catch {
            throw PersistenceError.validationFailed(error.applicationMessage)
        }

        let instance = RemoteInstance(name: sanitizedName, apiURL: sanitizedURL, secret: sanitizedSecret)
        let context = container.mainContext
        context.insert(instance)

        do {
            try context.save()
            try loadRemoteInstances()

            logger.info("Added remote instance: \(sanitizedName).")
        } catch {
            try? instance.clearSecret()
            throw mapError(error)
        }
    }

    func removeRemoteInstance(_ instance: RemoteInstance) throws(PersistenceError) {
        guard let container = modelContainer else {
            throw PersistenceError.notInitialized
        }

        let context = container.mainContext
        try? instance.clearSecret()
        context.delete(instance)

        do {
            try context.save()
            try loadRemoteInstances()

            logger.info("Removed remote instance: \(instance.name).")
        } catch {
            throw mapError(error)
        }
    }

    func activateRemoteInstance(_ instance: RemoteInstance?) async {
        guard let container = modelContainer else { return }
        let context = container.mainContext

        let deactivateDescriptor = FetchDescriptor<RemoteInstance>(
            predicate: #Predicate<RemoteInstance> { $0.isActive == true },
            )
        let activeInstances = try? context.fetch(deactivateDescriptor)
        for inst in activeInstances ?? [] {
            inst.isActive = false
        }

        if let instance {
            instance.isActive = true
            instance.lastConnected = Date()

            apiClient.configure(baseURL: instance.apiURL, secret: instance.secret)

            logger.info("Activated remote instance: \(instance.name).")
        } else {
            apiClient.configure(baseURL: "http://127.0.0.1:9090", secret: nil as String?)
            logger.info("Switched to local mode.")
        }

        try? modelContainer?.mainContext.save()

        apiClient.disconnect()
        await apiClient.connect()

        emitState()
    }

    private func sendNotification(title: String, body: String) async {
        await NotificationExtension.sendNotification(
            title: title,
            body: body,
            category: "CONFIG_CHANGE",
            )
    }
}

enum PersistenceError: MainError {
    case notInitialized
    case invalidURL
    case duplicateURL
    case downloadFailed
    case invalidEncoding
    case validationFailed(String)
    case secretStorageFailed(String)

    var category: ErrorCategory { .state }

    static var errorDomain: String { NSError.applicationErrorDomain }

    var errorCode: Int {
        switch self {
        case .notInitialized: 5001
        case .invalidURL: 5002
        case .duplicateURL: 5003
        case .downloadFailed: 5004
        case .invalidEncoding: 5005
        case .validationFailed: 5006
        case .secretStorageFailed: 5007
        }
    }

    var userFriendlyMessage: String {
        errorDescription ?? "Remote configuration operation failed"
    }

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Remote configuration manager is not initialized."

        case .invalidURL:
            "The URL is invalid."

        case .duplicateURL:
            "A configuration with this URL already exists."

        case .downloadFailed:
            "Failed to download configuration."

        case .invalidEncoding:
            "The configuration file uses an unsupported or invalid text encoding."

        case let .validationFailed(reason):
            "Configuration validation failed: \(reason)"

        case let .secretStorageFailed(reason):
            "Failed to store the secret securely: \(reason)"
        }
    }

    var failureReason: String? {
        switch self {
        case .notInitialized:
            "The persistence system has not been properly initialized"
        case .invalidURL:
            "The provided URL format is not valid"
        case .duplicateURL:
            "A configuration with the same URL is already registered"
        case .downloadFailed:
            "The remote configuration could not be downloaded"
        case .invalidEncoding:
            "The configuration file encoding is not supported"
        case .validationFailed:
            "The configuration content failed validation checks"
        case .secretStorageFailed:
            "The secret could not be stored in the keychain"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            "Initialize the persistence system before use"
        case .invalidURL:
            "Check the URL format and try again"
        case .duplicateURL:
            "Use a different URL or update the existing configuration"
        case .downloadFailed:
            "Check your network connection and try again"
        case .invalidEncoding:
            "Ensure the configuration file uses UTF-8 encoding"
        case .validationFailed:
            "Check the configuration format and content"
        case .secretStorageFailed:
            "Check keychain access permissions"
        }
    }

    var recoveryOptions: [String]? {
        switch self {
        case .notInitialized:
            ["Initialize", "Cancel"]
        case .invalidURL:
            ["Edit URL", "Cancel"]
        case .duplicateURL:
            ["Update Existing", "Use Different URL", "Cancel"]
        case .downloadFailed:
            ["Retry", "Check Connection", "Cancel"]
        case .invalidEncoding:
            ["Try Different Encoding", "Cancel"]
        case .validationFailed:
            ["Edit Configuration", "Skip Validation", "Cancel"]
        case .secretStorageFailed:
            ["Retry", "Skip Secret", "Cancel"]
        }
    }

    var helpAnchor: String? {
        "persistence-errors"
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
        return userInfo
    }
}
