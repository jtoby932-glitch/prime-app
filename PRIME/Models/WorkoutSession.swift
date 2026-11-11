import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var uuid: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var statusRaw: String = SessionStatus.active.rawValue
    var notes: String = ""
    var planID: UUID? = nil
    var bodyweightKg: Double? = nil
    /// Persisted so the rest timer survives the app being closed.
    var restEndsAt: Date? = nil
    var restTotalSeconds: Int = 0
    var restExerciseName: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSession.session)
    var exercises: [ExerciseSession] = []

    init(name: String, planID: UUID? = nil, bodyweightKg: Double? = nil, startedAt: Date = Date()) {
        self.uuid = UUID()
        self.name = name
        self.planID = planID
        self.bodyweightKg = bodyweightKg
        self.startedAt = startedAt
        self.statusRaw = SessionStatus.active.rawValue
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var isActive: Bool { status == .active }

    var sortedExercises: [ExerciseSession] { exercises.filter { !$0.isDeleted }.sorted { $0.position < $1.position } }

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    var completedSets: [ExerciseSet] {
        exercises.filter { !$0.isSkipped }.flatMap { $0.sets.filter(\.isCompleted) }
    }

    var totalVolume: Double {
        completedSets.filter { !$0.isWarmup }.reduce(0) { $0 + StrengthMath.setVolume(weight: $1.weightKg, reps: $1.reps) }
    }

    /// Completed sets ÷ planned sets, ignoring skipped exercises.
    var completion: Double {
        let active = exercises.filter { !$0.isSkipped }
        let total = active.reduce(0) { $0 + $1.sets.count }
        guard total > 0 else { return 0 }
        let done = active.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        return Double(done) / Double(total)
    }

    var nextPosition: Int { (exercises.map(\.position).max() ?? -1) + 1 }
}

@Model
final class ExerciseSession {
    var position: Int = 0
    var exerciseSlug: String = ""
    var exerciseName: String = ""
    /// Snapshots so history and analytics survive the exercise being deleted.
    var equipmentRaw: String = Equipment.barbell.rawValue
    var primaryMusclesRaw: [String] = []
    var notes: String = ""
    var isSkipped: Bool = false
    var restSeconds: Int = 90
    var targetReps: Int? = nil
    var targetWeightKg: Double? = nil
    var exercise: Exercise?
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exerciseSession)
    var sets: [ExerciseSet] = []

    init(position: Int, exercise: Exercise, restSeconds: Int, targetReps: Int? = nil, targetWeightKg: Double? = nil) {
        self.position = position
        self.restSeconds = restSeconds
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.exercise = exercise
        self.exerciseSlug = exercise.slug
        self.exerciseName = exercise.name
        self.equipmentRaw = exercise.equipmentRaw
        self.primaryMusclesRaw = exercise.primaryMusclesRaw
    }

    /// Re-points this entry at a different exercise, keeping its place in the workout.
    func adopt(_ exercise: Exercise) {
        self.exercise = exercise
        exerciseSlug = exercise.slug
        exerciseName = exercise.name
        equipmentRaw = exercise.equipmentRaw
        primaryMusclesRaw = exercise.primaryMusclesRaw
    }

    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .barbell }
    var primaryMuscles: [MuscleGroup] { MuscleGroup.from(primaryMusclesRaw) }
    var sortedSets: [ExerciseSet] { sets.filter { !$0.isDeleted }.sorted { $0.position < $1.position } }
    var completedSets: [ExerciseSet] { sortedSets.filter(\.isCompleted) }
    var nextSetPosition: Int { (sets.map(\.position).max() ?? -1) + 1 }

    var volume: Double {
        completedSets.filter { !$0.isWarmup }.reduce(0) { $0 + StrengthMath.setVolume(weight: $1.weightKg, reps: $1.reps) }
    }
}

@Model
final class ExerciseSet {
    var position: Int = 0
    var weightKg: Double? = nil
    var reps: Int? = nil
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var isWarmup: Bool = false
    var exerciseSession: ExerciseSession?

    init(position: Int, weightKg: Double? = nil, reps: Int? = nil, isWarmup: Bool = false) {
        self.position = position
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
    }
}
