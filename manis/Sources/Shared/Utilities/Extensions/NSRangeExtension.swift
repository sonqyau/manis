import Foundation
import Rearrange

extension NSRange {
    func intersects(_ other: NSRange) -> Bool {
        guard location != NSNotFound, other.location != NSNotFound else { return false }
        return NSIntersectionRange(self, other).length > 0
    }

    func contains(_ location: Int) -> Bool {
        guard self.location != NSNotFound else { return false }
        return NSLocationInRange(location, self)
    }

    func union(with other: NSRange) -> NSRange {
        guard location != NSNotFound, other.location != NSNotFound else {
            return location != NSNotFound ? self : other
        }
        return NSUnionRange(self, other)
    }

    var isEmpty: Bool {
        length == 0
    }

    var isValid: Bool {
        location != NSNotFound && length >= 0
    }
}

extension IndexSet {
    init(ranges: [NSRange]) {
        self.init()
        insert(ranges: ranges)
    }

    mutating func insert(ranges: [NSRange]) {
        for range in ranges {
            insert(range: range)
        }
    }

    mutating func insert(range: NSRange) {
        guard range.isValid else { return }
        if let swiftRange = Range(range) {
            insert(integersIn: swiftRange)
        }
    }

    mutating func remove(ranges: [NSRange]) {
        for range in ranges {
            remove(integersIn: range)
        }
    }

    var nsRangeView: [NSRange] {
        rangeView.map { NSRange($0) }
    }

    func contains(integersIn range: NSRange) -> Bool {
        guard range.isValid else { return false }
        return contains(integersIn: Range(range) ?? 0 ..< 0)
    }

    func intersects(integersIn range: NSRange) -> Bool {
        guard range.isValid else { return false }
        return intersects(integersIn: Range(range) ?? 0 ..< 0)
    }

    var limitSpanningRange: NSRange? {
        guard !isEmpty else { return nil }
        guard let first, let last else { return nil }
        return NSRange(location: first, length: last - first + 1)
    }
}

extension String {
    subscript(range: Range<Int>) -> Substring? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(startIndex, offsetBy: range.upperBound)
        return self[start ..< end]
    }

    subscript(range: NSRange) -> Substring? {
        guard range.isValid, range.max <= count else { return nil }
        return range.range(in: self).map { self[$0] }
    }

    func safeSubstring(in range: NSRange) -> String? {
        let clampedRange = range.clamped(to: count)
        return self[clampedRange].map(String.init)
    }

    func safeSubstring(in range: Range<Int>) -> String? {
        guard range.lowerBound >= 0 else { return nil }
        let clampedEnd = min(range.upperBound, count)
        let clampedRange = range.lowerBound ..< clampedEnd
        return self[clampedRange].map(String.init)
    }
}

struct TextMutationTracker {
    private(set) var mutations: [RangeMutation] = []

    mutating func addMutation(_ mutation: RangeMutation) {
        mutations.append(mutation)
    }

    func applyMutations(to range: NSRange) -> NSRange? {
        var currentRange = range

        for mutation in mutations {
            guard let updatedRange = currentRange.apply(mutation) else {
                return nil
            }
            currentRange = updatedRange
        }

        return currentRange
    }

    func applyMutations(to ranges: [NSRange]) -> [NSRange] {
        ranges.compactMap { applyMutations(to: $0) }
    }

    func applyMutations(to indexSet: IndexSet) -> IndexSet {
        var currentSet = indexSet

        for mutation in mutations {
            currentSet = mutation.transform(set: currentSet)
        }

        return currentSet
    }

    mutating func reset() {
        mutations.removeAll()
    }

    var isEmpty: Bool {
        mutations.isEmpty
    }
}

struct RangeCollection {
    private var ranges: [NSRange]

    init(_ ranges: [NSRange] = []) {
        self.ranges = ranges.filter(\.isValid)
    }

    mutating func add(_ range: NSRange) {
        guard range.isValid else { return }
        ranges.append(range)
    }

    mutating func remove(_ range: NSRange) {
        ranges.removeAll { $0.intersects(range) }
    }

    mutating func apply(_ mutation: RangeMutation) {
        ranges = ranges.compactMap { $0.apply(mutation) }
    }

    func intersecting(_ range: NSRange) -> [NSRange] {
        ranges.filter { $0.intersects(range) }
    }

    func containing(_ location: Int) -> [NSRange] {
        ranges.filter { $0.contains(location) }
    }

    var merged: [NSRange] {
        guard !ranges.isEmpty else { return [] }

        let sorted = ranges.sorted { $0.location < $1.location }
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

    var asIndexSet: IndexSet {
        IndexSet(ranges: ranges)
    }

    var isEmpty: Bool {
        ranges.isEmpty
    }

    var count: Int {
        ranges.count
    }
}
