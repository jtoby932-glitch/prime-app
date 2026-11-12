import Foundation
import SwiftData

/// The store layout shipped in PRIME 1.0, frozen exactly so SwiftData can migrate it.
/// Never edit these classes: change the current models and add a new schema version instead.
enum PrimeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, BodyweightEntry.self, Exercise.self, WorkoutPlan.self, PlannedExercise.self, WorkoutDay.self,
         WorkoutSession.self, ExerciseSession.self, ExerciseSet.self, PersonalRecord.self, PerformanceRanking.self]
    }

    @Model
    final class UserProfile {
        var name: String = ""
        @Attribute(.externalStorage) var photoData: Data? = nil
        var weightUnitRaw: String = "kg"
        var measurementSystemRaw: String = "metric"
        var experienceRaw: String = "beginner"
        var interestsRaw: [String] = []
        var preferredWeekdays: [Int] = []
        var heightCm: Double? = nil
        var defaultRestSeconds: Int = 90
        var weeklyGoal: Int = 3
        var tierScale: Double = 1.0
        var hasCompletedOnboarding: Bool = false
        var hasCreatedFirstWorkout: Bool = false
        var createdAt: Date = Date()
        var notifyScheduledWorkouts: Bool = false
        var notifyMissedWorkouts: Bool = false
        var notifyPersonalRecords: Bool = true
        var notifyRestTimer: Bool = true
        var scheduledReminderMinutes: Int = 1050
        var missedReminderMinutes: Int = 1200
        init() {}
    }

    @Model
    final class BodyweightEntry {
        var uuid: UUID = UUID()
        var date: Date = Date()
        var weightKg: Double = 0
        var note: String = ""
        init() {}
    }

    @Model
    final class Exercise {
        @Attribute(.unique) var slug: String = ""
        var name: String = ""
        var primaryMusclesRaw: [String] = []
        var secondaryMusclesRaw: [String] = []
        var equipmentRaw: String = "barbell"
        var mechanicRaw: String = "compound"
        var difficultyRaw: String = "beginner"
        var instructions: [String] = []
        var techniqueTips: [String] = []
        var commonMistakes: [String] = []
        var alternativeSlugs: [String] = []
        var isFavourite: Bool = false
        var isCustom: Bool = false
        var catalogueVersion: Int = 0
        var createdAt: Date = Date()
        var rankingMethodRaw: String = "load"
        var defaultThresholds: [Double] = []
        var customThresholds: [Double]? = nil
        var rankingNote: String = ""
        @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.exercise)
        var plannedEntries: [PlannedExercise] = []
        @Relationship(deleteRule: .nullify, inverse: \ExerciseSession.exercise)
        var loggedSessions: [ExerciseSession] = []
        init(slug: String, name: String) {
            self.slug = slug
            self.name = name
        }
    }

    @Model
    final class WorkoutPlan {
        var uuid: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var colorIndex: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.plan)
        var entries: [PlannedExercise] = []
        @Relationship(deleteRule: .nullify, inverse: \WorkoutDay.plan)
        var days: [WorkoutDay] = []
        init(name: String) { self.name = name }
    }

    @Model
    final class PlannedExercise {
        var position: Int = 0
        var exerciseSlug: String = ""
        var exerciseName: String = ""
        var targetSets: Int = 3
        var targetReps: Int = 10
        var targetWeightKg: Double? = nil
        var restSeconds: Int = 90
        var exercise: Exercise?
        var plan: WorkoutPlan?
        init() {}
    }

    @Model
    final class WorkoutDay {
        @Attribute(.unique) var weekday: Int = 0
        var isRest: Bool = false
        var plan: WorkoutPlan?
        init(weekday: Int) { self.weekday = weekday }
    }

    @Model
    final class WorkoutSession {
        var uuid: UUID = UUID()
        var name: String = ""
        var startedAt: Date = Date()
        var endedAt: Date? = nil
        var statusRaw: String = "active"
        var notes: String = ""
        var planID: UUID? = nil
        var bodyweightKg: Double? = nil
        var restEndsAt: Date? = nil
        var restTotalSeconds: Int = 0
        var restExerciseName: String = ""
        @Relationship(deleteRule: .cascade, inverse: \ExerciseSession.session)
        var exercises: [ExerciseSession] = []
        init(name: String) { self.name = name }
    }

    @Model
    final class ExerciseSession {
        var position: Int = 0
        var exerciseSlug: String = ""
        var exerciseName: String = ""
        var equipmentRaw: String = "barbell"
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
        init() {}
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
        init() {}
    }

    @Model
    final class PersonalRecord {
        var uuid: UUID = UUID()
        var exerciseSlug: String = ""
        var exerciseName: String = ""
        var kindRaw: String = "bestOneRepMax"
        var value: Double = 0
        var weightKg: Double = 0
        var reps: Int = 0
        var previousValue: Double? = nil
        var achievedAt: Date = Date()
        var sessionID: UUID? = nil
        init() {}
    }

    @Model
    final class PerformanceRanking {
        var uuid: UUID = UUID()
        var exerciseSlug: String = ""
        var exerciseName: String = ""
        var methodRaw: String = "load"
        var tierRaw: Int = 0
        var score: Double = 0
        var metric: Double = 0
        var estimatedOneRepMaxKg: Double? = nil
        var bodyweightKg: Double? = nil
        var weightKg: Double = 0
        var reps: Int = 0
        var usedCustomThresholds: Bool = false
        var standardsVersion: Int = 1
        var recordedAt: Date = Date()
        var sessionID: UUID? = nil
        init() {}
    }
}
