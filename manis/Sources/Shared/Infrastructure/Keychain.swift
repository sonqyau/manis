import Foundation
import Valet

final class Keychain: @unchecked Sendable {
    static let shared = Keychain()

    private let valet: Valet

    private init() {
        guard let identifier = Identifier(nonEmpty: "com.manis.secrets") else {
            fatalError("Failed to create keychain identifier")
        }
        self.valet = Valet.valet(with: identifier, accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    func setSecret(_ secret: String, for key: String) throws {
        do {
            try valet.setString(secret, forKey: key)
        } catch {
            throw mapError(error)
        }
    }

    func secret(for key: String) throws -> String? {
        do {
            return try valet.string(forKey: key)
        } catch {
            throw mapError(error)
        }
    }

    func deleteSecret(for key: String) throws {
        do {
            try valet.removeObject(forKey: key)
        } catch {
            throw mapError(error)
        }
    }

    func containsSecret(for key: String) throws -> Bool {
        do {
            return try valet.containsObject(forKey: key)
        } catch {
            throw mapError(error)
        }
    }

    func removeAllSecrets() throws {
        do {
            try valet.removeAllObjects()
        } catch {
            throw mapError(error)
        }
    }

    func allKeys() throws -> Set<String> {
        do {
            return try valet.allKeys()
        } catch {
            throw mapError(error)
        }
    }

    func canAccessKeychain() -> Bool {
        valet.canAccessKeychain()
    }

    private func mapError(_ error: Error) -> ManisKeychainError {
        if let valetError = error as? KeychainError {
            switch valetError {
            case .couldNotAccessKeychain:
                return .keychainUnavailable
            case .userCancelled:
                return .permissionDenied
            case .missingEntitlement:
                return .permissionDenied
            case .emptyKey, .emptyValue:
                return .stringEncodingFailure
            case .itemNotFound:
                return .unexpectedStatus(errSecItemNotFound)
            }
        }
        return .unexpectedStatus(-1)
    }
}

enum ManisKeychainError: MainError {
    case unexpectedStatus(OSStatus)
    case stringEncodingFailure
    case permissionDenied
    case keychainUnavailable

    var category: ErrorCategory { .permission }

    var errorCode: Int {
        switch self {
        case let .unexpectedStatus(status): Int(status)
        case .stringEncodingFailure: 8001
        case .permissionDenied: 8002
        case .keychainUnavailable: 8003
        }
    }

    var errorDomain: String { NSError.applicationErrorDomain }

    var userFriendlyMessage: String {
        switch self {
        case .unexpectedStatus:
            "Secure storage access denied. Verify system permissions."
        case .stringEncodingFailure:
            "Secret processing failed for secure storage."
        case .permissionDenied:
            "Access to secure storage was denied. Please grant keychain access."
        case .keychainUnavailable:
            "Secure storage is not available on this system."
        }
    }

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain operation failed: \(message)"
            }
            return "Keychain operation failed with status code \(status)"
        case .stringEncodingFailure:
            return "Secret encoding failed for secure storage"
        case .permissionDenied:
            return "Keychain access permission denied"
        case .keychainUnavailable:
            return "Keychain service is not available"
        }
    }

    var failureReason: String? {
        switch self {
        case .unexpectedStatus:
            "The keychain operation returned an unexpected status"
        case .stringEncodingFailure:
            "The secret could not be encoded to UTF-8 format"
        case .permissionDenied:
            "The system denied access to the keychain"
        case .keychainUnavailable:
            "The keychain service is not accessible"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unexpectedStatus:
            "Check system permissions and keychain access settings"
        case .stringEncodingFailure:
            "Ensure the secret contains valid text characters"
        case .permissionDenied:
            "Grant keychain access in System Preferences > Security & Privacy"
        case .keychainUnavailable:
            "Restart the application or check system keychain service"
        }
    }

    var recoveryOptions: [String]? {
        switch self {
        case .unexpectedStatus, .permissionDenied:
            ["Retry", "Check Permissions", "Cancel"]
        case .stringEncodingFailure:
            ["Try Different Text", "Cancel"]
        case .keychainUnavailable:
            ["Retry", "Cancel"]
        }
    }

    var helpAnchor: String? {
        "keychain-errors"
    }
}
