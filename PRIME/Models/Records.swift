import Foundation
import SwiftData

/// Keyed by slug rather than a relationship so records outlive a deleted custom exercise.
@Model
final class PersonalRecord {
    var uuid: UUID = UUID()
    var exerciseSlug: String = ""
    var exerciseName: String = ""
    var kindRaw: String = RecordKind.bestOneRepMax.rawValue
    var value: Double = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var previousValue: Double? = nil
    var achievedAt: Date = Date()
    var sessionID: UUID? = nil

    init(exerciseSlug: String, exerciseName: String, kind: RecordKind, value: Double, weightKg: Double, reps: Int,
         previousValue: Double?, achievedAt: Date, sessionID: UUID?) {
        self.uuid = UUID()
        self.exerciseSlug = exerciseSlug
        self.exerciseName = exerciseName
        self.kindRaw = kind.rawValue
        self.value = value
        self.weightKg = weightKg
        self.reps = reps
        self.previousValue = previousValue
        self.achievedAt = achievedAt
        self.sessionID = sessionID
    }

    var kind: RecordKind { RecordKind(rawValue: kindRaw) ?? .bestOneRepMax }
}

/// A snapshot of an exercise's rank after a workout, used for rank history charts.
@Model
final class PerformanceRanking {
    var uuid: UUID = UUID()
    var exerciseSlug: String = ""
    var exerciseName: String = ""
    var methodRaw: String = RankingMethod.relativeLoad.rawValue
    var tierRaw: Int = 0
    var score: Double = 0
    var metric: Double = 0
    var estimatedOneRepMaxKg: Double? = nil
    var bodyweightKg: Double? = nil
    var weightKg: Double = 0
    var reps: Int = 0
    var usedCustomThresholds: Bool = false
    var standardsVersion: Int = RankingStandard.version
    var recordedAt: Date = Date()
    var sessionID: UUID? = nil
    /// Entered through "Log a ranked performance" rather than derived from a workout (schema v2).
    /// Submitted entries are never rebuilt or overwritten.
    var isSubmitted: Bool = false

    init(exerciseSlug: String, exerciseName: String, result: RankResult, recordedAt: Date, sessionID: UUID?, isSubmitted: Bool = false) {
        self.isSubmitted = isSubmitted
        self.uuid = UUID()
        self.exerciseSlug = exerciseSlug
        self.exerciseName = exerciseName
        self.methodRaw = result.method.rawValue
        self.tierRaw = result.placement.tier.rawValue
        self.score = result.placement.score
        self.metric = result.metric
        self.estimatedOneRepMaxKg = result.estimatedOneRepMaxKg
        self.bodyweightKg = result.set.bodyweightKg
        self.weightKg = result.set.weightKg
        self.reps = result.set.reps
        self.usedCustomThresholds = result.usedCustomThresholds
        self.standardsVersion = RankingStandard.version
        self.recordedAt = recordedAt
        self.sessionID = sessionID
    }

    var tier: RankTier { RankTier(rawValue: tierRaw) ?? .unranked }
    var isTestedMax: Bool { reps == 1 && method == .relativeLoad }
    var rankableSet: RankableSet { RankableSet(weightKg: weightKg, reps: reps, date: recordedAt, bodyweightKg: bodyweightKg) }
    var method: RankingMethod { RankingMethod(rawValue: methodRaw) ?? .relativeLoad }
}
