import Foundation

/// A recommendation that was actually shown to the user, persisted so that
/// outcomes can reference it and future recommendations can learn from
/// it.
struct StoredRecommendation: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let recommendedTime: Date
    let confidence: Double
    let reasonCodes: [RecommendationReason]
    let createdAt: Date

    init(
        recommendation: ReminderRecommendation,
        createdAt: Date,
        id: UUID = UUID()
    ) {
        self.id = id
        self.taskID = recommendation.taskID
        self.recommendedTime = recommendation.recommendedTime
        self.confidence = recommendation.confidence
        self.reasonCodes = recommendation.reasonCodes
        self.createdAt = createdAt
    }

    init(
        id: UUID,
        taskID: UUID,
        recommendedTime: Date,
        confidence: Double,
        reasonCodes: [RecommendationReason],
        createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.recommendedTime = recommendedTime
        self.confidence = confidence
        self.reasonCodes = reasonCodes
        self.createdAt = createdAt
    }
}
