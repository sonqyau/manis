import AppKit
import Foundation
import Rearrange

@MainActor
final class TextCoordinator: ObservableObject {
    @Published var text: String = ""
    @Published var searchResults: [TextComposer.SearchResult] = []
    @Published var currentSearchIndex: Int = 0

    private var mutationTracker = TextMutationTracker()
    private var rangeCollection = RangeCollection()

    var hasSearchResults: Bool {
        !searchResults.isEmpty
    }

    var currentSearchResult: TextComposer.SearchResult? {
        guard hasSearchResults, currentSearchIndex < searchResults.count else { return nil }
        return searchResults[currentSearchIndex]
    }

    func search(_ query: String, options: NSString.CompareOptions = [.caseInsensitive]) {
        searchResults = TextComposer.findAll(query, in: text, options: options)
        currentSearchIndex = 0
    }

    func nextSearchResult() {
        guard hasSearchResults else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }

    func previousSearchResult() {
        guard hasSearchResults else { return }
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchResults.count - 1
    }

    func replaceCurrentMatch(with replacement: String) {
        guard let currentResult = currentSearchResult else { return }

        let operation = TextComposer.ReplaceOperation(
            range: currentResult.range,
            replacement: replacement,
            originalText: currentResult.matchedText,
        )

        performReplaceOperation(operation)
    }

    func replaceAll(_ searchText: String, with replacement: String, options: NSString.CompareOptions = [.caseInsensitive]) {
        let (newText, operations) = TextComposer.replaceAll(searchText, with: replacement, in: text, options: options)

        text = newText

        for operation in operations {
            mutationTracker.addMutation(operation.mutation)
        }

        updateSearchResults()
    }

    func insertText(_ insertText: String, at location: Int) {
        let (newText, mutation) = TextComposer.insertText(insertText, at: location, in: text)
        text = newText
        mutationTracker.addMutation(mutation)
        updateSearchResults()
    }

    func deleteText(in range: NSRange) {
        let (newText, mutation) = TextComposer.deleteText(in: range, from: text)
        text = newText
        mutationTracker.addMutation(mutation)
        updateSearchResults()
    }

    func addHighlightRange(_ range: NSRange) {
        rangeCollection.add(range)
    }

    func removeHighlightRange(_ range: NSRange) {
        rangeCollection.remove(range)
    }

    func clearHighlights() {
        rangeCollection = RangeCollection()
    }

    func getHighlightedRanges() -> [NSRange] {
        rangeCollection.merged
    }

    func createAttributedString(with baseAttributes: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        let searchHighlightAttributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.3),
        ]

        let currentMatchAttributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.5),
        ]

        let customHighlightAttributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.2),
        ]

        TextComposer.highlightRanges(
            getHighlightedRanges(),
            in: attributedString,
            with: customHighlightAttributes,
        )

        TextComposer.highlightRanges(
            searchResults.map(\.range),
            in: attributedString,
            with: searchHighlightAttributes,
        )

        if let currentResult = currentSearchResult {
            TextComposer.highlightRanges(
                [currentResult.range],
                in: attributedString,
                with: currentMatchAttributes,
            )
        }

        return attributedString
    }

    func getLineRange(containing location: Int) -> NSRange? {
        TextComposer.findLineRange(containing: location, in: text)
    }

    func extractLines(in range: NSRange) -> [String] {
        TextComposer.extractLines(from: text, in: range)
    }

    func validateRange(_ range: NSRange) -> NSRange? {
        TextComposer.validateTextRange(range, in: text)
    }

    func resetMutationTracking() {
        mutationTracker.reset()
    }

    func getMutationHistory() -> Bool {
        !mutationTracker.isEmpty
    }

    private func performReplaceOperation(_ operation: TextComposer.ReplaceOperation) {
        guard let substring = text[operation.range] else { return }

        text = text.replacingOccurrences(
            of: String(substring),
            with: operation.replacement,
        )

        mutationTracker.addMutation(operation.mutation)
        updateSearchResults()
    }

    private func updateSearchResults() {
        guard hasSearchResults else { return }

        var updatedResults: [TextComposer.SearchResult] = []

        for result in searchResults {
            if let updatedRange = mutationTracker.applyMutations(to: result.range) {
                let updatedResult = TextComposer.SearchResult(range: updatedRange, in: text)
                updatedResults.append(updatedResult)
            }
        }

        searchResults = updatedResults

        if currentSearchIndex >= searchResults.count {
            currentSearchIndex = max(0, searchResults.count - 1)
        }

        rangeCollection.apply(mutationTracker.mutations.last ?? RangeMutation(range: .zero, delta: 0))
    }
}

extension TextCoordinator {
    struct SearchOptions: OptionSet {
        let rawValue: Int

        static let caseInsensitive = Self(rawValue: 1 << 0)
        static let wholeWords = Self(rawValue: 1 << 1)
        static let regularExpression = Self(rawValue: 1 << 2)
        static let backwards = Self(rawValue: 1 << 3)

        var nsStringOptions: NSString.CompareOptions {
            var options: NSString.CompareOptions = []

            if contains(.caseInsensitive) {
                options.insert(.caseInsensitive)
            }

            if contains(.regularExpression) {
                options.insert(.regularExpression)
            }

            if contains(.backwards) {
                options.insert(.backwards)
            }

            return options
        }
    }

    func advancedSearch(_ query: String, options: SearchOptions) {
        search(query, options: options.nsStringOptions)
    }

    func searchInRange(_ query: String, range: NSRange, options: SearchOptions = [.caseInsensitive]) -> [TextComposer.SearchResult] {
        guard let substring = text[range] else { return [] }
        let rangeText = String(substring)

        let results = TextComposer.findAll(query, in: rangeText, options: options.nsStringOptions)

        return results.map { result in
            let adjustedRange = NSRange(
                location: range.location + result.range.location,
                length: result.range.length,
            )
            return TextComposer.SearchResult(range: adjustedRange, in: text)
        }
    }
}
