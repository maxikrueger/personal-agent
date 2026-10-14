import Foundation

/// Closes the loop: recorded outcomes adjust the confidence of future
/// recommendations. Deterministic and bounded — outcomes can shift confidence
/// by at most ±0.1.
enum RecommendationEvaluator {
    /// Outcomes needed for full positive/negative weight.
    static let saturationCount = 3.0
    static let maxAdjustment = 0.1

    static func summary(from outcomes: [RecommendationOutcome]) -> RecommendationOutcomeSummary {
        var summary = RecommendationOutcomeSummary()
        for outcome in outcomes {
            switch outcome.outcome {
            case .accepted: summary.accepted += 1
            case .rejected: summary.rejected += 1
            case .ignored: summary.ignored += 1
            case .snoozed: summary.snoozed += 1
            case .completed: summary.completed += 1
            case .notCompleted: summary.notCompleted += 1
            }
        }
        return summary
    }

    /// Completions after recommendations raise confidence; rejections and
    /// ignores lower it. Result ∈ [-0.1, +0.1].
    static func confidenceAdjustment(for summary: RecommendationOutcomeSummary) -> Double {
        let positive = maxAdjustment * min(1, Double(summary.completed) / saturationCount)
        let negative = maxAdjustment * min(1, Double(summary.rejected + summary.ignored) / saturationCount)
        return positive - negative
    }
}
