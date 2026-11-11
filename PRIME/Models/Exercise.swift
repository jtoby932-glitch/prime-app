import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var slug: String = ""
    var name: String = ""
    var primaryMusclesRaw: [String] = []
    var secondaryMusclesRaw: [String] = []
    var equipmentRaw: String = Equipment.barbell.rawValue
    var mechanicRaw: String = Mechanic.compound.rawValue
    var difficultyRaw: String = Difficulty.beginner.rawValue
    var instructions: [String] = []
    var techniqueTips: [String] = []
    var commonMistakes: [String] = []
    var alternativeSlugs: [String] = []
    var isFavourite: Bool = false
    var isCustom: Bool = false
    var catalogueVersion: Int = 0
    var createdAt: Date = Date()

    var rankingMethodRaw: String = RankingMethod.relativeLoad.rawValue
    var defaultThresholds: [Double] = []
    var customThresholds: [Double]? = nil
    var rankingNote: String = ""

    /// Deleting an exercise removes it from routines, but logged history keeps its own copy of the name.
    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.exercise)
    var plannedEntries: [PlannedExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \ExerciseSession.exercise)
    var loggedSessions: [ExerciseSession] = []

    init(slug: String, name: String) {
        self.slug = slug
        self.name = name
        self.createdAt = Date()
    }

    var primaryMuscles: [MuscleGroup] {
        get { MuscleGroup.from(primaryMusclesRaw) }
        set { primaryMusclesRaw = newValue.map(\.rawValue) }
    }

    var secondaryMuscles: [MuscleGroup] {
        get { MuscleGroup.from(secondaryMusclesRaw) }
        set { secondaryMusclesRaw = newValue.map(\.rawValue) }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }

    var mechanic: Mechanic {
        get { Mechanic(rawValue: mechanicRaw) ?? .compound }
        set { mechanicRaw = newValue.rawValue }
    }

    var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .beginner }
        set { difficultyRaw = newValue.rawValue }
    }

    var rankingMethod: RankingMethod {
        get { RankingMethod(rawValue: rankingMethodRaw) ?? .unranked }
        set { rankingMethodRaw = newValue.rawValue }
    }

    var rankingStandard: RankingStandard {
        if let custom = customThresholds, RankingStandard.isValid(custom) {
            return RankingStandard(method: rankingMethod, thresholds: custom, isCustom: true, note: rankingNote)
        }
        return RankingStandard(method: rankingMethod, thresholds: defaultThresholds, isCustom: false, note: rankingNote)
    }

    var isRanked: Bool {
        rankingMethod != .unranked && RankingStandard.isValid(customThresholds ?? defaultThresholds)
    }

    var primaryMuscleSummary: String {
        primaryMuscles.map(\.displayName).joined(separator: ", ")
    }
}

extension Exercise: ExerciseDescribing {
    var displayName: String { name }
    var favourite: Bool { isFavourite }
}
