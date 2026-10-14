import Foundation

/// Candidate scoring weights. Configurable in code, never
/// exposed to the language model; defaults sum to 1.0.
struct RecommendationWeights: Sendable {
    var urgency = 0.30
    var preferredWindow = 0.30
    var procrastination = 0.15
    var deadlineFit = 0.15
    var earliness = 0.10
}

struct RecommendationConfig: Sendable {
    var weights = RecommendationWeights()
    /// Assumed time needed to work on a task; candidate slots must fit it.
    var taskDuration: TimeInterval = 1800
    /// How many days ahead candidate times are searched.
    var horizonDays = 3
    /// Deadline distance at which urgency reaches zero.
    var urgencyHorizon: TimeInterval = 7 * 86_400
    /// Candidates are only proposed within these local hours.
    var wakingStartHour = 8
    var wakingEndHour = 21

    var searchHorizon: TimeInterval {
        Double(horizonDays) * 86_400
    }

    static let standard = RecommendationConfig()
}
