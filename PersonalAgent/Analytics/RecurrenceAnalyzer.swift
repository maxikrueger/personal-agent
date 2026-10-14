import Foundation

/// Detects recurring completion behavior from completion timestamps
/// without requiring an explicit repeating reminder.
enum RecurrenceAnalyzer {
    /// Fewer completions than this → no inference at all.
    static let minimumCompletions = 3
    /// An interval matches a nominal pattern length within this relative tolerance.
    static let patternTolerance = 0.25
    /// Below this confidence no pattern is claimed.
    static let confidenceThreshold = 0.5
    /// Intervals needed for full sample-size weight.
    static let fullSampleIntervals = 6.0

    private static let day: TimeInterval = 86_400
    private static let nominalPatterns: [(pattern: RecurrencePattern, days: Double)] = [
        (.daily, 1),
        (.weekly, 7),
        (.biweekly, 14),
        (.monthly, 30.44),
    ]

    static func analyze(completionDates: [Date], calendar: Calendar) -> RecurrenceAnalysis {
        let sorted = completionDates.sorted()
        guard sorted.count >= minimumCompletions else {
            return RecurrenceAnalysis(pattern: nil, confidence: 0, sampleSize: sorted.count)
        }

        let intervals = zip(sorted.dropFirst(), sorted).map { later, earlier in
            later.timeIntervalSince(earlier) / day
        }
        guard let medianDays = medianValue(of: intervals), medianDays > 0 else {
            return RecurrenceAnalysis(pattern: nil, confidence: 0, sampleSize: sorted.count)
        }

        let consistent = intervals.filter { abs($0 - medianDays) <= medianDays * patternTolerance }
        let consistency = Double(consistent.count) / Double(intervals.count)
        let sampleFactor = min(1.0, Double(intervals.count) / fullSampleIntervals)
        let confidence = consistency * sampleFactor

        guard confidence >= confidenceThreshold else {
            return RecurrenceAnalysis(pattern: nil, confidence: confidence, sampleSize: sorted.count)
        }

        var pattern = nominalPatterns.first { candidate in
            abs(medianDays - candidate.days) <= candidate.days * patternTolerance
        }?.pattern ?? .irregular

        if pattern == .daily,
           sorted.count >= 5,
           sorted.allSatisfy({ !calendar.isDateInWeekend($0) }) {
            pattern = .everyWeekday
        }

        return RecurrenceAnalysis(pattern: pattern, confidence: confidence, sampleSize: sorted.count)
    }

    private static func medianValue(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
