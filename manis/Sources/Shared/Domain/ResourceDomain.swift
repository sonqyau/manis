import Compression
import Foundation
import NonEmpty
import OSLog
import SystemPackage

@MainActor
@Observable
final class ResourceDomain {
    static let shared = ResourceDomain()

    private let logger = MainLog.shared.logger(for: .core)

    let configDirectory: URL
    let configFilePath: URL
    let geoIPDatabasePath: URL
    let geoSiteDatabasePath: URL
    let geoIPv6DatabasePath: URL

    var isInitialized = false
    var initializationError: (any Error)?

    private init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        configDirectory =
            homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("clash", isDirectory: true)

        configFilePath = configDirectory.appendingPathComponent("config.yaml")
        geoIPDatabasePath = configDirectory.appendingPathComponent("Country.mmdb")
        geoSiteDatabasePath = configDirectory.appendingPathComponent("geosite.dat")
        geoIPv6DatabasePath = configDirectory.appendingPathComponent("GeoLite2-Country.mmdb")
    }

    func initialize() async throws {
        do {
            try createConfigDirectoryIfNeeded()
            try await ensureGeoIPDatabase()
            try await ensureGeoSiteDatabase()

            isInitialized = true
            initializationError = nil
            logger.info("Resource initialization complete")
        } catch {
            isInitialized = false
            initializationError = error
            let chain = error.errorChainDescription
            logger.error("Resource initialization failed\n\(chain)", error: error)
            throw error
        }
    }

    private func createConfigDirectoryIfNeeded() throws {
        let configPath = configDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: configPath.path, isDirectory: &isDir)

        if exists, isDir.boolValue {
            return
        }
        if exists, !isDir.boolValue {
            throw ResourceError.configDirectoryIsFile
        }

        do {
            try performFile {
                try FileManager.default.createDirectory(
                    atPath: configPath.path,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755],
                    )
            }
        } catch {
            throw ResourceError.cannotCreateConfigDirectory(error)
        }
    }

    private func ensureGeoIPDatabase() async throws {
        let geoIPPath = geoIPDatabasePath
        if FileManager.default.fileExists(atPath: geoIPPath.path) {
            if isGeoIPDatabaseValid() {
                logger.debug("GeoIP database valid")
                return
            }
            try? FileManager.default.removeItem(atPath: geoIPPath.path)
        }

        try extractBundledGeoIPDatabase()
        logger.info("GeoIP database extracted")
    }

    private func getResourceURL(forResource name: String, withExtension ext: String?) -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "miho_miho", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let resourceURL = bundle.url(forResource: name, withExtension: ext) {
            return resourceURL
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func isGeoIPDatabaseValid() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: geoIPDatabasePath.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size > 1_000_000
    }

    private func extractBundledGeoIPDatabase() throws {
        guard let path = getResourceURL(forResource: "Country.mmdb", withExtension: "lzfse") else {
            if let uncompressed = getResourceURL(forResource: "Country", withExtension: "mmdb") {
                try FileManager.default.copyItem(at: uncompressed, to: geoIPDatabasePath)
                return
            }
            throw ResourceError.bundledGeoIPNotFound
        }

        let compressed = try Data(contentsOf: path)
        let decompressed = try decompressLZFSE(compressed)
        let geoIPPath = FilePath(geoIPDatabasePath.path)
        let fd = try FileDescriptor.open(geoIPPath, .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644))
        _ = try fd.closeAfter {
            try fd.writeAll(decompressed)
        }
    }

    private func ensureGeoSiteDatabase() async throws {
        if FileManager.default.fileExists(atPath: geoSiteDatabasePath.path) {
            return
        }

        guard let path = getResourceURL(forResource: "geosite.dat", withExtension: "lzfse")
        else { return }

        do {
            let compressed = try Data(contentsOf: path)
            let decompressed = try decompressLZFSE(compressed)
            let geoSitePath = FilePath(geoSiteDatabasePath.path)
            let fd = try FileDescriptor.open(geoSitePath, .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644))
            _ = try fd.closeAfter {
                try fd.writeAll(decompressed)
            }
        } catch {
            logger.error("GeoSite extract failed", error: error)
        }
    }

    func updateGeoIPDatabase() async throws {
        let mihomoDomain = MihomoDomain()
        let apis = [mihomoDomain.upgradeGeo1, mihomoDomain.upgradeGeo2]
        guard let updateAPI = apis.randomElement() else {
            throw ResourceError.updateFailed(NSError(domain: "ResourceDomain", code: -1))
        }
        try await updateAPI()
    }

    func ensureDefaultConfig() throws {
        if FileManager.default.fileExists(atPath: configFilePath.path) {
            return
        }

        guard let bundled = getResourceURL(forResource: "config", withExtension: "yaml") else {
            throw ResourceError.bundledConfigNotFound
        }

        try FileManager.default.copyItem(at: bundled, to: configFilePath)
    }

    func listConfigFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: configDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
            )
        .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()
    }

    func configPath(for name: String) -> URL {
        configDirectory.appendingPathComponent("\(name).yaml")
    }

    private func performFile<T>(_ operation: () throws -> T) throws -> T {
        try operation()
    }

    private func decompressLZFSE(_ data: Data) throws -> Data {
        let decompressed = try (data as NSData).decompressed(using: .lzfse) as Data
        guard NonEmpty(rawValue: decompressed) != nil else { throw ResourceError.decompressionFailed }
        return decompressed
    }
}

enum ResourceError: MainError {
    case configDirectoryIsFile
    case cannotCreateConfigDirectory(any Error)
    case bundledGeoIPNotFound
    case cannotExtractGeoIP(any Error)
    case bundledConfigNotFound
    case cannotCreateConfig(any Error)
    case decompressionFailed
    case updateFailed(any Error)

    var category: ErrorCategory { .file }

    static var errorDomain: String { NSError.applicationErrorDomain }

    var errorCode: Int {
        switch self {
        case .configDirectoryIsFile: 6001
        case .cannotCreateConfigDirectory: 6002
        case .bundledGeoIPNotFound: 6003
        case .cannotExtractGeoIP: 6004
        case .bundledConfigNotFound: 6005
        case .cannotCreateConfig: 6006
        case .decompressionFailed: 6007
        case .updateFailed: 6008
        }
    }

    var userFriendlyMessage: String {
        errorDescription ?? "Resource operation failed"
    }

    var errorDescription: String? {
        switch self {
        case .configDirectoryIsFile:
            "Configuration path exists but is a file, not a directory."

        case let .cannotCreateConfigDirectory(error):
            "Configuration directory creation failed: \(error.localizedDescription)"

        case .bundledGeoIPNotFound:
            "Bundled GeoIP database not found in the application bundle."

        case let .cannotExtractGeoIP(error):
            "GeoIP database extraction failed: \(error.localizedDescription)"

        case .bundledConfigNotFound:
            "Bundled configuration file not found in the application bundle."

        case let .cannotCreateConfig(error):
            "Configuration file creation failed: \(error.localizedDescription)"

        case .decompressionFailed:
            "Failed to decompress LZFSE data."

        case let .updateFailed(error):
            "Resource update operation failed: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .configDirectoryIsFile:
            "Remove the file at ~/.config/clash, then restart the application."

        case .cannotCreateConfigDirectory:
            "Verify file system permissions and ensure you have write access to ~/.config."

        case .bundledGeoIPNotFound:
            "The application bundle may be corrupted. Reinstall the application."

        case .cannotExtractGeoIP:
            "Check available disk space and file system permissions."

        case .bundledConfigNotFound:
            "The application bundle may be corrupted. Reinstall the application."

        case .cannotCreateConfig:
            "Check file system permissions."

        case .decompressionFailed:
            "The bundled database file may be corrupted. Reinstall the application."

        case .updateFailed:
            "Check your network connection and try again."
        }
    }

    var failureReason: String? {
        switch self {
        case .configDirectoryIsFile:
            "A file exists where a directory is expected"
        case .cannotCreateConfigDirectory:
            "Directory creation failed due to file system constraints"
        case .bundledGeoIPNotFound:
            "Required GeoIP database is missing from application bundle"
        case .cannotExtractGeoIP:
            "GeoIP database extraction process failed"
        case .bundledConfigNotFound:
            "Required configuration file is missing from application bundle"
        case .cannotCreateConfig:
            "Configuration file creation failed"
        case .decompressionFailed:
            "Data decompression operation failed"
        case .updateFailed:
            "Resource update operation failed"
        }
    }

    var recoveryOptions: [String]? {
        switch self {
        case .configDirectoryIsFile:
            ["Remove File", "Choose Different Location", "Cancel"]
        case .cannotCreateConfigDirectory:
            ["Retry", "Check Permissions", "Cancel"]
        case .bundledGeoIPNotFound, .bundledConfigNotFound:
            ["Reinstall App", "Download Manually", "Cancel"]
        case .cannotExtractGeoIP, .cannotCreateConfig:
            ["Retry", "Check Disk Space", "Cancel"]
        case .decompressionFailed:
            ["Retry", "Reinstall App", "Cancel"]
        case .updateFailed:
            ["Retry", "Check Connection", "Cancel"]
        }
    }

    var helpAnchor: String? {
        "resource-errors"
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

        switch self {
        case let .cannotCreateConfigDirectory(error), let .cannotExtractGeoIP(error),
             let .cannotCreateConfig(error), let .updateFailed(error):
            userInfo[NSUnderlyingErrorKey] = error
        default:
            break
        }

        return userInfo
    }
}
