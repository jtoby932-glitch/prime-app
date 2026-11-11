import Foundation
import SwiftData

@MainActor
enum DataService {
    static func profile(in context: ModelContext) -> UserProfile {
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first { return existing }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    @discardableResult
    static func logBodyweight(_ kilograms: Double, on date: Date = Date(), context: ModelContext) -> BodyweightEntry {
        let entry = BodyweightEntry(date: date, weightKg: kilograms)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Writes every completed set to a CSV file in the user's chosen unit.
    static func exportCSV(history: TrainingHistory, unit: WeightUnit) throws -> URL {
        var lines = ["Date,Workout,Exercise,Set,Weight (\(unit.symbol)),Reps,Est. 1RM (\(unit.symbol)),Volume (\(unit.symbol))"]
        let names = Dictionary(history.sessions.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        for sample in history.samples {
            let e1rm = sample.estimatedOneRepMax.map { Format.number(unit.fromKilograms($0), maxFractionDigits: 1) } ?? ""
            let row = [
                dateFormatter.string(from: sample.date),
                csvEscape(names[sample.sessionID] ?? ""),
                csvEscape(sample.exerciseName),
                String(sample.setIndex + 1),
                Format.number(unit.fromKilograms(sample.weightKg)),
                String(sample.reps),
                e1rm,
                Format.number(unit.fromKilograms(sample.volume), maxFractionDigits: 1),
            ]
            lines.append(row.joined(separator: ","))
        }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PRIME-history-\(stamp).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Erases all personal data and returns the catalogue to its shipped state.
    static func eraseEverything(context: ModelContext) throws {
        func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
            for item in try context.fetch(FetchDescriptor<T>()) { context.delete(item) }
        }
        try deleteAll(ExerciseSet.self)
        try deleteAll(ExerciseSession.self)
        try deleteAll(WorkoutSession.self)
        try deleteAll(PlannedExercise.self)
        try deleteAll(WorkoutPlan.self)
        try deleteAll(WorkoutDay.self)
        try deleteAll(PersonalRecord.self)
        try deleteAll(PerformanceRanking.self)
        try deleteAll(BodyweightEntry.self)
        try deleteAll(UserProfile.self)
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            if exercise.isCustom {
                context.delete(exercise)
            } else {
                exercise.isFavourite = false
                exercise.customThresholds = nil
            }
        }
        try context.save()
        NotificationService.shared.removeAll()
    }
}
