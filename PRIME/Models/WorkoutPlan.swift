import Foundation
import SwiftData

/// A reusable routine, e.g. "Push Day".
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

    init(name: String, notes: String = "", colorIndex: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.notes = notes
        self.colorIndex = colorIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// SwiftData doesn't keep array order, so entries carry an explicit position.
    var sortedEntries: [PlannedExercise] { entries.filter { !$0.isDeleted }.sorted { $0.position < $1.position } }

    var assignedWeekdays: [Int] { days.filter { !$0.isRest }.map(\.weekday).sorted() }

    var totalSets: Int { entries.reduce(0) { $0 + $1.targetSets } }

    /// Rough minutes: ~40 s of work plus the planned rest per set.
    var estimatedMinutes: Int {
        let seconds = entries.reduce(0) { $0 + $1.targetSets * (40 + $1.restSeconds) }
        return max(5, Int((Double(seconds) / 60).rounded()))
    }

    var muscles: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for entry in sortedEntries {
            for muscle in entry.exercise?.primaryMuscles ?? [] where !seen.contains(muscle) { seen.append(muscle) }
        }
        return seen
    }
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

    init(position: Int, exercise: Exercise, targetSets: Int = 3, targetReps: Int = 10, targetWeightKg: Double? = nil, restSeconds: Int = 90) {
        self.position = position
        self.exercise = exercise
        self.exerciseSlug = exercise.slug
        self.exerciseName = exercise.name
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.restSeconds = restSeconds
    }
}

/// One of the seven days in the weekly timetable.
@Model
final class WorkoutDay {
    /// 0 = Monday … 6 = Sunday
    @Attribute(.unique) var weekday: Int = 0
    var isRest: Bool = false
    var plan: WorkoutPlan?

    init(weekday: Int) {
        self.weekday = weekday
    }

    enum State: Equatable {
        case unplanned, rest, training
    }

    var state: State {
        if isRest { return .rest }
        return plan == nil ? .unplanned : .training
    }
}
