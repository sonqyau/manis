import Algorithms
import Foundation
import Rearrange

public enum TextComposer {
    public struct SearchResult {
        let range: NSRange
        let matchedText: String
        let context: String?

        public init(range: NSRange, in text: String, contextLength: Int = 50) {
            self.range = range
            self.matchedText = text[range].map(String.init) ?? ""

            let contextStart = max(0, range.location - contextLength)
            let contextEnd = min(text.count, range.max + contextLength)
            let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
            self.context = text[contextRange].map(String.init)
        }
    }

    public struct ReplaceOperation {
        let range: NSRange
        let replacement: String
        let originalText: String

        public var mutation: RangeMutation {
            RangeMutation(range: range, delta: replacement.count - originalText.count)
        }
    }

    public static func findAll(
        _ searchText: String,
        in text: String,
        options: NSString.CompareOptions = [.caseInsensitive],
        contextLength: Int = 50,
        ) -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }

        var results: [SearchResult] = []
        var searchRange = NSRange(location: 0, length: text.count)

        while searchRange.location < text.count {
            let foundRange = (text as NSString).range(
                of: searchText,
                options: options,
                range: searchRange,
                )

            if foundRange.location == NSNotFound {
                break
            }

            let result = SearchResult(range: foundRange, in: text, contextLength: contextLength)
            results.append(result)

            searchRange = NSRange(
                location: foundRange.max,
                length: text.count - foundRange.max,
                )
        }

        return results
    }

    public static func replaceAll(
        _ searchText: String,
        with replacement: String,
        in text: String,
        options: NSString.CompareOptions = [.caseInsensitive],
        ) -> (result: String, operations: [ReplaceOperation]) {
        let searchResults = findAll(searchText, in: text, options: options)
        guard !searchResults.isEmpty else {
            return (text, [])
        }

        let operations = searchResults.reversed().indexed().map { _, result in
            let adjustedRange = NSRange(
                location: result.range.location,
                length: result.range.length,
                )

            let operation = ReplaceOperation(
                range: adjustedRange,
                replacement: replacement,
                originalText: result.matchedText,
                )
            return operation
        }

        let currentText = operations.reversed().reduce(text) { currentText, operation in
            if let substring = currentText[operation.range] {
                return currentText.replacingOccurrences(
                    of: String(substring),
                    with: operation.replacement,
                    options: [],
                    range: Range(operation.range, in: currentText),
                    )
            }
            return currentText
        }

        return (currentText, operations.reversed())
    }

    public static func insertText(
        _ insertText: String,
        at location: Int,
        in text: String,
        ) -> (result: String, mutation: RangeMutation) {
        let clampedLocation = max(0, min(location, text.count))
        let insertRange = NSRange(location: clampedLocation, length: 0)
        let mutation = RangeMutation(range: insertRange, delta: insertText.count)

        let startIndex = text.index(text.startIndex, offsetBy: clampedLocation)
        let result = String(text.prefix(upTo: startIndex)) + insertText + String(text.suffix(from: startIndex))

        return (result, mutation)
    }

    public static func deleteText(
        in range: NSRange,
        from text: String,
        ) -> (result: String, mutation: RangeMutation) {
        let clampedRange = range.clamped(to: text.count)
        let mutation = RangeMutation(range: clampedRange, delta: -clampedRange.length)

        guard let substring = text[clampedRange] else {
            return (text, mutation)
        }

        let result = text.replacingOccurrences(of: String(substring), with: "")
        return (result, mutation)
    }

    public static func extractLines(
        from text: String,
        in range: NSRange,
        ) -> [String] {
        let clampedRange = range.clamped(to: text.count)
        guard let substring = text[clampedRange] else { return [] }

        return String(substring).components(separatedBy: .newlines)
    }

    public static func findLineRange(
        containing location: Int,
        in text: String,
        ) -> NSRange? {
        guard location >= 0, location <= text.count else { return nil }

        let nsString = text as NSString
        return nsString.lineRange(for: NSRange(location: location, length: 0))
    }

    public static func highlightRanges(
        _ ranges: [NSRange],
        in attributedString: NSMutableAttributedString,
        with attributes: [NSAttributedString.Key: Any],
        ) {
        for range in ranges {
            let clampedRange = range.clamped(to: attributedString.length)
            attributedString.addAttributes(attributes, range: clampedRange)
        }
    }

    public static func validateTextRange(
        _ range: NSRange,
        in text: String,
        allowEmpty: Bool = true,
        ) -> NSRange? {
        guard range.location != NSNotFound else { return nil }
        guard range.location >= 0 else { return nil }
        guard range.max <= text.count else { return nil }
        guard allowEmpty || range.length > 0 else { return nil }

        return range
    }

    public static func mergeOverlappingRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }

        let validRanges = ranges.filter(\.isValid)
        guard !validRanges.isEmpty else { return [] }

        let sorted = validRanges.sorted { $0.location < $1.location }
        var merged: [NSRange] = [sorted[0]]

        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.location <= last.max {
                merged[merged.count - 1] = last.union(with: range)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    public static func splitTextByRanges(
        _ text: String,
        ranges: [NSRange],
        ) -> [String] {
        let sortedRanges = ranges.filter(\.isValid).sorted { $0.location < $1.location }
        guard !sortedRanges.isEmpty else { return [text] }

        let chunkedRanges = sortedRanges.chunked { current, next in
            current.max <= next.location
        }

        var parts: [String] = []
        var currentLocation = 0

        for chunk in chunkedRanges {
            let clampedRanges = chunk.map { $0.clamped(to: text.count) }

            if let firstRange = clampedRanges.first, currentLocation < firstRange.location {
                let beforeRange = NSRange(
                    location: currentLocation,
                    length: firstRange.location - currentLocation,
                    )
                if let beforeText = text[beforeRange] {
                    parts.append(String(beforeText))
                }
            }

            for range in clampedRanges {
                if let rangeText = text[range] {
                    parts.append(String(rangeText))
                }
            }

            if let lastRange = clampedRanges.last {
                currentLocation = lastRange.max
            }
        }

        if currentLocation < text.count {
            let afterRange = NSRange(
                location: currentLocation,
                length: text.count - currentLocation,
                )
            if let afterText = text[afterRange] {
                parts.append(String(afterText))
            }
        }

        return parts
    }
}
