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
        var lines = ["Date,Workout,Exercise,Set,Weight (\(unit.symbol)),Reps or seconds,Est. 1RM (\(unit.symbol)),Volume (\(unit.symbol))"]
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

    /// Everything the user created, as one JSON document: profile, bodyweight, routines,
    /// timetable, workouts with every set, records and rank history.
    static func exportJSON(context: ModelContext) throws -> URL {
        let iso = ISO8601DateFormatter()
        func date(_ value: Date?) -> Any { value.map { iso.string(from: $0) } ?? NSNull() }
        func optional(_ value: Any?) -> Any { value ?? NSNull() }

        let profile = (try context.fetch(FetchDescriptor<UserProfile>())).first
        let bodyweights = try context.fetch(FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.date)]))
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.createdAt)]))
        let days = try context.fetch(FetchDescriptor<WorkoutDay>(sortBy: [SortDescriptor(\.weekday)]))
        let completed = SessionStatus.completed.rawValue
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == completed },
                                                                        sortBy: [SortDescriptor(\.startedAt)]))
        let records = try context.fetch(FetchDescriptor<PersonalRecord>(sortBy: [SortDescriptor(\.achievedAt)]))
        let rankings = try context.fetch(FetchDescriptor<PerformanceRanking>(sortBy: [SortDescriptor(\.recordedAt)]))
        let custom = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.isCustom || $0.isFavourite || $0.customThresholds != nil }

        typealias Object = [String: Any]
        var profileObject: Object = ["name": profile?.name ?? "", "weightUnit": profile?.weightUnitRaw ?? "kg"]
        profileObject["experience"] = profile?.experienceRaw ?? ""
        profileObject["weeklyGoal"] = profile?.weeklyGoal ?? 3
        profileObject["heightCm"] = optional(profile?.heightCm)
        profileObject["tierScale"] = profile?.tierScale ?? 1

        let bodyweightObjects: [Object] = bodyweights.map { entry -> Object in ["date": date(entry.date), "kg": entry.weightKg] }

        var routineObjects: [Object] = []
        for plan in plans {
            var entries: [Object] = []
            for entry in plan.sortedEntries {
                var object: Object = ["exercise": entry.exerciseName, "slug": entry.exerciseSlug, "sets": entry.targetSets]
                object["reps"] = entry.targetReps
                object["targetKg"] = optional(entry.targetWeightKg)
                object["restSeconds"] = entry.restSeconds
                entries.append(object)
            }
            routineObjects.append(["name": plan.name, "notes": plan.notes, "fromPreset": optional(plan.sourceTemplateID), "exercises": entries])
        }

        let dayObjects: [Object] = days.map { day -> Object in
            ["day": Weekday.longNames[day.weekday], "rest": day.isRest, "routine": optional(day.plan?.name)]
        }

        var workoutObjects: [Object] = []
        for session in sessions {
            var items: [Object] = []
            for item in session.sortedExercises {
                let sets: [Object] = item.completedSets.map { set -> Object in
                    ["kg": optional(set.weightKg), "reps": optional(set.reps), "warmup": set.isWarmup]
                }
                items.append(["exercise": item.exerciseName, "slug": item.exerciseSlug, "skipped": item.isSkipped, "notes": item.notes, "sets": sets])
            }
            var object: Object = ["name": session.name, "started": date(session.startedAt), "ended": date(session.endedAt)]
            object["notes"] = session.notes
            object["bodyweightKg"] = optional(session.bodyweightKg)
            object["readiness"] = optional(session.readiness)
            object["exercises"] = items
            workoutObjects.append(object)
        }

        let recordObjects: [Object] = records.map { record -> Object in
            var object: Object = ["exercise": record.exerciseName, "kind": record.kindRaw, "value": record.value]
            object["kg"] = record.weightKg
            object["reps"] = record.reps
            object["date"] = date(record.achievedAt)
            return object
        }

        let rankObjects: [Object] = rankings.map { entry -> Object in
            var object: Object = ["exercise": entry.exerciseName, "tier": entry.tier.name, "metric": entry.metric]
            object["kg"] = entry.weightKg
            object["reps"] = entry.reps
            object["bodyweightKg"] = optional(entry.bodyweightKg)
            object["submitted"] = entry.isSubmitted
            object["date"] = date(entry.recordedAt)
            return object
        }

        let exerciseObjects: [Object] = custom.map { exercise -> Object in
            var object: Object = ["name": exercise.name, "slug": exercise.slug, "custom": exercise.isCustom]
            object["favourite"] = exercise.isFavourite
            object["customTiers"] = optional(exercise.customThresholds)
            return object
        }

        var document: Object = ["format": "PRIME export", "version": 2, "exportedAt": iso.string(from: Date()), "weightsIn": "kg"]
        document["profile"] = profileObject
        document["bodyweight"] = bodyweightObjects
        document["routines"] = routineObjects
        document["timetable"] = dayObjects
        document["workouts"] = workoutObjects
        document["personalRecords"] = recordObjects
        document["rankHistory"] = rankObjects
        document["exercises"] = exerciseObjects
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PRIME-export-\(stamp).json")
        try data.write(to: url, options: .atomic)
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
