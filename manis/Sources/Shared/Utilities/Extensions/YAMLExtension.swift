import Foundation
import Yams

struct YAMLDecoder {
    enum YAMLDecodingError: MainError {
        case invalidUTF8
        case malformedYAML(String)
        case decodingFailed(Error)

        var category: ErrorCategory { .parsing }

        var errorCode: Int {
            switch self {
            case .invalidUTF8: 4001
            case .malformedYAML: 4002
            case .decodingFailed: 4003
            }
        }

        var errorDomain: String { NSError.applicationErrorDomain }

        var userFriendlyMessage: String {
            switch self {
            case .invalidUTF8:
                "The file contains invalid text encoding."
            case .malformedYAML:
                "The YAML format is invalid."
            case .decodingFailed:
                "Failed to process the YAML data."
            }
        }

        var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                "Invalid UTF-8 encoding in YAML data"
            case let .malformedYAML(details):
                "Malformed YAML: \(details)"
            case let .decodingFailed(error):
                "YAML decoding failed: \(error.localizedDescription)"
            }
        }

        var failureReason: String? {
            switch self {
            case .invalidUTF8:
                "The YAML data contains invalid UTF-8 characters"
            case .malformedYAML:
                "The YAML syntax is incorrect or corrupted"
            case .decodingFailed:
                "The YAML structure does not match the expected format"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidUTF8:
                "Ensure the file is saved with UTF-8 encoding"
            case .malformedYAML:
                "Check the YAML syntax and fix any formatting errors"
            case .decodingFailed:
                "Verify the YAML structure matches the expected schema"
            }
        }

        var recoveryOptions: [String]? {
            switch self {
            case .invalidUTF8:
                ["Fix Encoding", "Try Different File", "Cancel"]
            case .malformedYAML:
                ["Fix Syntax", "Use Default", "Cancel"]
            case .decodingFailed:
                ["Fix Structure", "Use Default", "Cancel"]
            }
        }

        var helpAnchor: String? {
            "yaml-parsing-errors"
        }
    }

    func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        do {
            let str = try ByteProcessor.processUTF8Data(data)
            let decoder = Yams.YAMLDecoder()
            return try decoder.decode(T.self, from: str)
        } catch _ as ByteProcessor.ByteProcessingError {
            throw YAMLDecodingError.invalidUTF8
        } catch {
            throw YAMLDecodingError.decodingFailed(error)
        }
    }

    func decode<T: Decodable>(_: T.Type, from string: String) throws -> T {
        _ = string.utf8Span
        let decoder = Yams.YAMLDecoder()
        do {
            return try decoder.decode(T.self, from: string)
        } catch {
            throw YAMLDecodingError.decodingFailed(error)
        }
    }
}

extension YAMLDecoder {}

enum YAMLExtension {}
