import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = ""
    @Attribute(.externalStorage) var photoData: Data? = nil
    var weightUnitRaw: String = WeightUnit.kg.rawValue
    var measurementSystemRaw: String = MeasurementSystem.metric.rawValue
    var experienceRaw: String = ExperienceLevel.beginner.rawValue
    var interestsRaw: [String] = []
    /// 0 = Monday … 6 = Sunday
    var preferredWeekdays: [Int] = []
    var heightCm: Double? = nil
    var defaultRestSeconds: Int = 90
    var weeklyGoal: Int = 3
    /// Multiplies every provisional ranking threshold (0.5…1.5).
    var tierScale: Double = 1.0
    var hasCompletedOnboarding: Bool = false
    var hasCreatedFirstWorkout: Bool = false
    var createdAt: Date = Date()

    var notifyScheduledWorkouts: Bool = false
    var notifyMissedWorkouts: Bool = false
    var notifyPersonalRecords: Bool = true
    var notifyRestTimer: Bool = true
    /// Minutes after midnight.
    var scheduledReminderMinutes: Int = 1050
    var missedReminderMinutes: Int = 1200

    init() {}

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    var measurementSystem: MeasurementSystem {
        get { MeasurementSystem(rawValue: measurementSystemRaw) ?? .metric }
        set { measurementSystemRaw = newValue.rawValue }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .beginner }
        set { experienceRaw = newValue.rawValue }
    }

    var interests: [TrainingInterest] {
        get { interestsRaw.compactMap(TrainingInterest.init(rawValue:)) }
        set { interestsRaw = newValue.map(\.rawValue) }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Athlete" : trimmed
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

@Model
final class BodyweightEntry {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0
    var note: String = ""

    init(date: Date = Date(), weightKg: Double, note: String = "") {
        self.uuid = UUID()
        self.date = date
        self.weightKg = weightKg
        self.note = note
    }
}
