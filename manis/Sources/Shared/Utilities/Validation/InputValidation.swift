import Foundation

enum InputValidationError: MainError {
    case emptyField(String)
    case invalidCharacters(String)
    case invalidURL
    case disallowedScheme
    case invalidSecret

    static var errorDomain: String { NSError.applicationErrorDomain }

    var category: ErrorCategory { .validation }

    var errorCode: Int {
        switch self {
        case .emptyField: 9001
        case .invalidCharacters: 9002
        case .invalidURL: 9003
        case .disallowedScheme: 9004
        case .invalidSecret: 9005
        }
    }

    var recoverySuggestion: String? { "Check the input format and try again" }
    var recoveryOptions: [String]? { ["Edit", "Cancel"] }
    var helpAnchor: String? { "input-validation-errors" }

    var userFriendlyMessage: String {
        errorDescription ?? "Input validation failed"
    }

    var errorDescription: String? {
        switch self {
        case let .emptyField(name):
            "\(name) must not be empty"

        case let .invalidCharacters(name):
            "\(name) contains characters that are not permitted"

        case .invalidURL:
            "The provided URL is not valid"

        case .disallowedScheme:
            "URL scheme must be HTTP or HTTPS"

        case .invalidSecret:
            "The provided secret is not valid"
        }
    }

    var failureReason: String? {
        switch self {
        case .emptyField:
            "Required field was left empty"
        case .invalidCharacters:
            "Field contains prohibited characters"
        case .invalidURL:
            "URL format is not recognized"
        case .disallowedScheme:
            "URL uses an unsupported protocol"
        case .invalidSecret:
            "Secret format is invalid"
        }
    }
}

enum InputValidation {
    private static let identifierAllowedCharacterSet: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_ ")
        return allowed
    }()

    static func sanitizedIdentifier(_ value: String, fieldName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InputValidationError.emptyField(fieldName)
        }

        guard trimmed.count <= 64 else {
            throw InputValidationError.invalidCharacters("\(fieldName) exceeds 64 characters")
        }

        guard trimmed.unicodeScalars.allSatisfy({ identifierAllowedCharacterSet.contains($0) }) else {
            throw InputValidationError.invalidCharacters(fieldName)
        }

        return trimmed
    }

    static func sanitizedURLString(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InputValidationError.emptyField("URL")
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty,
              components.host != nil
        else {
            throw InputValidationError.invalidURL
        }

        guard ["http", "https"].contains(scheme) else {
            throw InputValidationError.disallowedScheme
        }

        return trimmed
    }

    static func sanitizedSecret(_ value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        guard trimmed.count <= 256,
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw InputValidationError.invalidSecret
        }

        return trimmed
    }
}
