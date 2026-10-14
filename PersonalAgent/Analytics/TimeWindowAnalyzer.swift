import Foundation

/// Determines when the user tends to complete this task.
enum TimeWindowAnalyzer {
    /// Fewer completions than this → no preference is inferred.
    static let minimumCompletions = 3

    static func analyze(completionDates: [Date], calendar: Calendar) -> PreferredWindowAnalysis {
        let sampleSize = completionDates.count
        guard sampleSize >= minimumCompletions else {
            return PreferredWindowAnalysis(window: nil, confidence: 0, sampleSize: sampleSize)
        }

        var counts: [TimeWindow: Int] = [:]
        for date in completionDates {
            let hour = calendar.component(.hour, from: date)
            counts[TimeWindow.window(forHour: hour), default: 0] += 1
        }

        // Fixed window order makes ties deterministic.
        var best = TimeWindow.allWindows[0]
        var bestCount = counts[best] ?? 0
        for window in TimeWindow.allWindows.dropFirst() {
            let count = counts[window] ?? 0
            if count > bestCount {
                best = window
                bestCount = count
            }
        }

        return PreferredWindowAnalysis(
            window: best,
            confidence: Double(bestCount) / Double(sampleSize),
            sampleSize: sampleSize
        )
    }
}
