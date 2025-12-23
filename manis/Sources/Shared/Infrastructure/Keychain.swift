import Foundation
import Security

final class Keychain: @unchecked Sendable {
    static let shared = Keychain()

    private let service = "com.manis.secrets"

    private init() {}

    private func performKeychain<T>(_ operation: () throws -> T) throws -> T {
        try operation()
    }

    func setSecret(_ secret: String, for key: String) throws {
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmedSecret.data(using: .utf8) else {
            throw KeychainError.stringEncodingFailure
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let attributesToUpdate: [CFString: Any] = [kSecValueData: data]

        let status: OSStatus = try performKeychain {
            SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        }

        switch status {
        case errSecSuccess:
            return

        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus: OSStatus = try performKeychain {
                SecItemAdd(addQuery as CFDictionary, nil)
            }
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }

        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func secret(for key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]

        var item: CFTypeRef?
        let status: OSStatus = try performKeychain {
            SecItemCopyMatching(query as CFDictionary, &item)
        }

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.unexpectedStatus(errSecInternalError)
            }
            guard let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.stringEncodingFailure
            }
            return secret

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func deleteSecret(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]

        let status: OSStatus = try performKeychain {
            SecItemDelete(query as CFDictionary)
        }

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return

        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: MainError {
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
            "Unable to access secure storage. Please check your system permissions."
        case .stringEncodingFailure:
            "Unable to process the secret for secure storage."
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
            return "Unable to encode secret for secure storage"
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
