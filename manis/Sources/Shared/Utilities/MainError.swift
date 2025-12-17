import Foundation
import AppKit

extension NSError {
    @_optimize(speed)
    @inlinable
    static var applicationErrorDomain: String { "com.manis.application.error" }

    @_optimize(speed)
    @inlinable
    static var proxyDaemonErrorDomain: String { "com.manis.proxy.daemon.error" }

    @_optimize(speed)
    @inlinable
    static var networkDaemonErrorDomain: String { "com.manis.network.daemon.error" }

    @_optimize(speed)
    @inlinable
    static var systemProxyErrorDomain: String { "com.manis.system.proxy.error" }
}

extension NSError {
    @_optimize(speed)
    @inlinable
    static var errorCategoryKey: String { "ApplicationErrorCategory" }

    @_optimize(speed)
    @inlinable
    static var userFriendlyMessageKey: String { "ApplicationUserFriendlyMessage" }

    @_optimize(speed)
    @inlinable
    static var customRecoveryOptionsKey: String { "ApplicationRecoveryOptions" }

    @_optimize(speed)
    @inlinable
    static var customHelpAnchorKey: String { "ApplicationHelpAnchor" }
}

@frozen public enum ErrorCategory: UInt8, CaseIterable {
    case database = 0, file, network, validation, state, operation, permission, parsing, generic

    @_optimize(speed)
    @inlinable
    public var stringValue: String {
        switch self {
        case .database: "database"
        case .file: "file"
        case .network: "network"
        case .validation: "validation"
        case .state: "state"
        case .operation: "operation"
        case .permission: "permission"
        case .parsing: "parsing"
        case .generic: "generic"
        }
    }

    @_optimize(speed)
    @inlinable
    public var displayName: String {
        switch self {
        case .database: "Database"
        case .file: "File"
        case .network: "Network"
        case .validation: "Validation"
        case .state: "State"
        case .operation: "Operation"
        case .permission: "Permission"
        case .parsing: "Parsing"
        case .generic: "Error"
        }
    }

    @_optimize(speed)
    @inlinable
    public init?(stringValue: String) {
        switch stringValue {
        case "database": self = .database
        case "file": self = .file
        case "network": self = .network
        case "validation": self = .validation
        case "state": self = .state
        case "operation": self = .operation
        case "permission": self = .permission
        case "parsing": self = .parsing
        case "generic": self = .generic
        default: return nil
        }
    }
}

public protocol MainError: Error, CustomNSError, LocalizedError {
    var category: ErrorCategory { get }
    var userFriendlyMessage: String { get }
    var recoverySuggestion: String? { get }
    var recoveryOptions: [String]? { get }
    var helpAnchor: String? { get }
}

public extension MainError {
    @_optimize(speed)
    @inlinable
    var errorUserInfo: [String: Any] {
        var userInfo = [String: Any](minimumCapacity: 8)
        userInfo.reserveCapacity(8)

        if let desc = errorDescription { userInfo[NSLocalizedDescriptionKey] = desc }
        if let reason = failureReason { userInfo[NSLocalizedFailureReasonErrorKey] = reason }
        if let suggestion = recoverySuggestion { userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion }
        if let options = recoveryOptions { userInfo[NSLocalizedRecoveryOptionsErrorKey] = options }
        if let anchor = helpAnchor { userInfo[NSHelpAnchorErrorKey] = anchor }

        userInfo[NSError.errorCategoryKey] = category.stringValue
        userInfo[NSError.userFriendlyMessageKey] = userFriendlyMessage

        return userInfo
    }
}

public extension Error {
    @_optimize(speed)
    @inlinable
    var userFriendlyMessage: String {
        if let applicationError = self as? MainError {
            return applicationError.userFriendlyMessage
        }
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription
        {
            return description
        }
        return localizedDescription
    }

    @_optimize(speed)
    var errorChainDescription: String {
        var descriptions: [String] = []
        descriptions.reserveCapacity(4)
        var currentError: Error? = self

        while let error = currentError {
            descriptions.append(error.localizedDescription)
            currentError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }

        return descriptions.joined(separator: " -> ")
    }

    @_optimize(speed)
    func asNSError(domain: String = NSError.applicationErrorDomain, code: Int = 0) -> NSError {
        var userInfo = [String: Any](minimumCapacity: 6)
        userInfo[NSLocalizedDescriptionKey] = localizedDescription

        if let applicationError = self as? MainError {
            userInfo[NSError.userFriendlyMessageKey] = applicationError.userFriendlyMessage
            userInfo[NSError.errorCategoryKey] = applicationError.category.stringValue
            if let anchor = applicationError.helpAnchor {
                userInfo[NSHelpAnchorErrorKey] = anchor
            }
        }

        if let localizedError = self as? LocalizedError {
            if let reason = localizedError.failureReason {
                userInfo[NSLocalizedFailureReasonErrorKey] = reason
            }
            if let suggestion = localizedError.recoverySuggestion {
                userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
            }
        }

        let nsError = self as NSError
        if nsError.domain != domain || nsError.code != code {
            userInfo[NSUnderlyingErrorKey] = nsError
        }

        return NSError(domain: domain, code: code, userInfo: userInfo)
    }

    @_optimize(speed)
    @inlinable
    func asMainError() -> AppError { AppError(error: self) }

    @_optimize(speed)
    @inlinable
    var applicationMessage: String { userFriendlyMessage }

    @_optimize(speed)
    @inlinable
    var applicationRecoverySuggestion: String? {
        (self as? LocalizedError)?.recoverySuggestion
    }
}

extension ErrorCategory {
    @_optimize(speed)
    static func from(_ error: any Error) -> ErrorCategory {
        if let applicationError = error as? MainError {
            return applicationError.category
        }

        let errorType = type(of: error)

        if errorType is URLError.Type { return .network }
        if errorType is CocoaError.Type { return .file }
        if errorType is DecodingError.Type { return .parsing }

        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain: return .file
        case NSURLErrorDomain: return .network
        default: return .generic
        }
    }
}

@frozen public struct AppError {
    public let error: any Error
    public let nsError: NSError
    public let message: String
    public let recoverySuggestion: String?
    public let category: ErrorCategory
    public let recoveryOptions: [String]?
    public let helpAnchor: String?

    @_optimize(speed)
    public init(error: any Error) {
        self.error = error
        self.message = error.applicationMessage
        self.recoverySuggestion = error.applicationRecoverySuggestion
        self.category = ErrorCategory.from(error)

        if let applicationError = error as? MainError {
            self.nsError = NSError(
                domain: type(of: applicationError).errorDomain,
                code: applicationError.errorCode,
                userInfo: applicationError.errorUserInfo,
            )
            self.recoveryOptions = applicationError.recoveryOptions
            self.helpAnchor = applicationError.helpAnchor
        } else {
            self.nsError = error.asNSError()
            self.recoveryOptions = nil
            self.helpAnchor = nil
        }
    }

    @_optimize(speed)
    @inlinable
    public init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.init(error: NSError(domain: domain, code: code, userInfo: userInfo))
    }

    @_optimize(speed)
    public static func create(
        domain: String = NSError.applicationErrorDomain,
        code: Int,
        description: String,
        failureReason: String? = nil,
        recoverySuggestion: String? = nil,
        recoveryOptions: [String]? = nil,
        helpAnchor: String? = nil,
        underlyingError: Error? = nil,
        category: ErrorCategory = .generic,
    ) -> Self {
        var userInfo = [String: Any](minimumCapacity: 8)
        userInfo[NSLocalizedDescriptionKey] = description

        if let reason = failureReason { userInfo[NSLocalizedFailureReasonErrorKey] = reason }
        if let suggestion = recoverySuggestion { userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion }
        if let options = recoveryOptions { userInfo[NSLocalizedRecoveryOptionsErrorKey] = options }
        if let anchor = helpAnchor { userInfo[NSHelpAnchorErrorKey] = anchor }
        if let underlying = underlyingError { userInfo[NSUnderlyingErrorKey] = underlying }

        userInfo[NSError.errorCategoryKey] = category.stringValue

        return Self(domain: domain, code: code, userInfo: userInfo)
    }
}

extension NSError {
    @_optimize(speed)
    convenience init(
        applicationErrorDomain domain: String = NSError.applicationErrorDomain,
        code: Int,
        description: String,
        failureReason: String? = nil,
        recoverySuggestion: String? = nil,
        recoveryOptions: [String]? = nil,
        helpAnchor: String? = nil,
        underlyingError: Error? = nil,
        category: ErrorCategory = .generic,
    ) {
        var userInfo = [String: Any](minimumCapacity: 8)
        userInfo[NSLocalizedDescriptionKey] = description

        if let reason = failureReason { userInfo[NSLocalizedFailureReasonErrorKey] = reason }
        if let suggestion = recoverySuggestion { userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion }
        if let options = recoveryOptions { userInfo[NSLocalizedRecoveryOptionsErrorKey] = options }
        if let anchor = helpAnchor { userInfo[NSHelpAnchorErrorKey] = anchor }
        if let underlying = underlyingError { userInfo[NSUnderlyingErrorKey] = underlying }

        userInfo[NSError.errorCategoryKey] = category.stringValue

        self.init(domain: domain, code: code, userInfo: userInfo)
    }

    @_optimize(speed)
    @inlinable
    var applicationCategory: ErrorCategory? {
        guard let categoryString = userInfo[NSError.errorCategoryKey] as? String else { return nil }
        return ErrorCategory(stringValue: categoryString)
    }

    @_optimize(speed)
    @inlinable
    var userFriendlyMessage: String? {
        userInfo[NSError.userFriendlyMessageKey] as? String
    }

    @_optimize(speed)
    var underlyingErrors: [Error] {
        var errors: [Error] = []
        errors.reserveCapacity(4)
        var currentError = userInfo[NSUnderlyingErrorKey] as? Error

        while let error = currentError {
            errors.append(error)
            currentError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }

        return errors
    }
}

public final class ErrorRecovery: NSObject {
    @_optimize(speed)
    public static func attemptRecovery(from error: Error, optionIndex: Int, delegate _: Any? = nil) -> Bool {
        let nsError = error as NSError
        guard let recoveryOptions = nsError.localizedRecoveryOptions,
              optionIndex < recoveryOptions.count else { return false }

        let selectedOption = recoveryOptions[optionIndex]

        switch selectedOption.lowercased() {
        case "retry": return true
        case "cancel": return false
        default:
            return false
        }
    }
}

public enum TypedError<T: Error>: Error {
    case wrapped(T)
    case other(Error)

    @_optimize(speed)
    @inlinable
    static func `catch`<Result>(_ operation: () throws -> Result) throws(T) -> Result {
        do {
            return try operation()
        } catch let error as T {
            throw error
        } catch {
            fatalError("Unexpected error type: \(error)")
        }
    }
}
