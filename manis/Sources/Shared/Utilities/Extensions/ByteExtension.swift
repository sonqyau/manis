import Foundation
import Rearrange

enum ByteProcessor {
    @inlinable
    static func processUTF8Data(_ data: Data) throws -> String {
        guard let str = String(validating: data, as: UTF8.self) else {
            throw ByteProcessingError.invalidUTF8
        }
        return str
    }

    @inlinable
    static func extractSubstring(
        _ string: borrowing String,
        in range: Range<String.Index>,
    ) -> String {
        String(string[range])
    }

    @inlinable
    static func safeSubstring(
        _ string: String,
        nsRange: NSRange,
    ) -> String? {
        string[nsRange].map(String.init)
    }

    @inlinable
    static func safeSubstring(
        _ string: String,
        range: Range<Int>,
    ) -> String? {
        string[range].map(String.init)
    }

    @inlinable
    static func processValidatedCString(_ cString: UnsafePointer<CChar>) throws -> String {
        guard let str = String(validatingCString: cString) else {
            throw ByteProcessingError.invalidCString
        }
        return str
    }

    @inlinable
    static func processBuffer<T>(_ buffer: UnsafeBufferPointer<T>) -> [T] {
        Array(buffer)
    }

    @inlinable
    static func clampedRange(_ range: NSRange, to limit: Int) -> NSRange {
        range.clamped(to: limit)
    }

    @inlinable
    static func shiftedRange(_ range: NSRange, by delta: Int) -> NSRange? {
        range.shifted(by: delta)
    }
}

extension ByteProcessor {
    enum ByteProcessingError: MainError {
        case invalidUTF8
        case invalidCString
        case bufferOverflow

        var category: ErrorCategory { .parsing }

        var errorCode: Int {
            switch self {
            case .invalidUTF8: 4101
            case .invalidCString: 4102
            case .bufferOverflow: 4103
            }
        }

        var errorDomain: String { NSError.applicationErrorDomain }

        var userFriendlyMessage: String {
            switch self {
            case .invalidUTF8:
                "The data contains invalid text encoding."
            case .invalidCString:
                "The text string is corrupted."
            case .bufferOverflow:
                "The data is too large to process."
            }
        }

        var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                "Invalid UTF-8 encoding in data"
            case .invalidCString:
                "Invalid C string format"
            case .bufferOverflow:
                "Buffer overflow during processing"
            }
        }

        var failureReason: String? {
            switch self {
            case .invalidUTF8:
                "The data contains bytes that are not valid UTF-8"
            case .invalidCString:
                "The C string is malformed or corrupted"
            case .bufferOverflow:
                "The buffer size exceeded safe limits"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidUTF8:
                "Ensure the data is properly encoded as UTF-8"
            case .invalidCString:
                "Check the source of the string data"
            case .bufferOverflow:
                "Reduce the data size or increase buffer limits"
            }
        }

        var recoveryOptions: [String]? {
            switch self {
            case .invalidUTF8:
                ["Fix Encoding", "Try Different Format", "Cancel"]
            case .invalidCString:
                ["Retry", "Use Different Source", "Cancel"]
            case .bufferOverflow:
                ["Reduce Size", "Increase Limit", "Cancel"]
            }
        }

        var helpAnchor: String? {
            "byte-processing-errors"
        }
    }
}

struct ByteExtension {}
