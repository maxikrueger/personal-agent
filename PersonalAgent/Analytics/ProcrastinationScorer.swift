import Foundation

/// Weights for the procrastination score. Configurable in
/// code, never exposed to the language model. Defaults sum to 1.0.
struct ProcrastinationWeights: Sendable {
    var postponementRate = 0.35
    var overdueRate = 0.25
    var delay = 0.20
    var age = 0.10
    var consecutivePostponements = 0.10

    static let standard = ProcrastinationWeights()
}

struct ProcrastinationInputs: Equatable, Sendable {
    /// 0…1 share of moves that were postponements.
    let postponementRate: Double
    /// 0…1 share of cycles that ended (or currently are) overdue.
    let overdueRate: Double
    /// Signed average lateness vs. due date; negative (early) counts as zero.
    let averageDelay: TimeInterval?
    /// How long the current open period has lasted; nil when completed.
    let openAge: TimeInterval?
    let consecutivePostponements: Int
}

enum ProcrastinationScorer {
    /// A week of average lateness saturates the delay component.
    static let delayNormalization: TimeInterval = 7 * 86_400
    /// A month of sitting open saturates the age component.
    static let ageNormalization: TimeInterval = 30 * 86_400
    /// Five consecutive postponements saturate the streak component.
    static let consecutiveNormalization = 5.0

    static func score(
        _ inputs: ProcrastinationInputs,
        weights: ProcrastinationWeights = .standard
    ) -> Double {
        let delayComponent = min(1, max(0, inputs.averageDelay ?? 0) / delayNormalization)
        let ageComponent = min(1, max(0, inputs.openAge ?? 0) / ageNormalization)
        let consecutiveComponent = min(
            1,
            Double(inputs.consecutivePostponements) / consecutiveNormalization
        )
        let raw = weights.postponementRate * min(1, max(0, inputs.postponementRate))
            + weights.overdueRate * min(1, max(0, inputs.overdueRate))
            + weights.delay * delayComponent
            + weights.age * ageComponent
            + weights.consecutivePostponements * consecutiveComponent
        return min(1, max(0, raw))
    }
}
