import Foundation
import SwiftData

@MainActor
enum ScheduleService {
    /// Makes sure all seven timetable days exist and returns them Monday first.
    @discardableResult
    static func ensureWeek(context: ModelContext) -> [WorkoutDay] {
        let existing = (try? context.fetch(FetchDescriptor<WorkoutDay>())) ?? []
        var byWeekday: [Int: WorkoutDay] = [:]
        for day in existing where byWeekday[day.weekday] == nil { byWeekday[day.weekday] = day }
        var created = false
        for weekday in Weekday.all where byWeekday[weekday] == nil {
            let day = WorkoutDay(weekday: weekday)
            context.insert(day)
            byWeekday[weekday] = day
            created = true
        }
        if created { try? context.save() }
        return Weekday.all.compactMap { byWeekday[$0] }
    }

    static func assign(_ plan: WorkoutPlan, to day: WorkoutDay, context: ModelContext) {
        day.plan = plan
        day.isRest = false
        try? context.save()
    }

    static func setRest(_ day: WorkoutDay, context: ModelContext) {
        day.plan = nil
        day.isRest = true
        try? context.save()
    }

    static func clear(_ day: WorkoutDay, context: ModelContext) {
        day.plan = nil
        day.isRest = false
        try? context.save()
    }

    /// Moves a day's workout to another day. If the target already has something, they swap.
    static func move(from source: WorkoutDay, to target: WorkoutDay, context: ModelContext) {
        guard source.weekday != target.weekday else { return }
        let sourcePlan = source.plan, sourceRest = source.isRest
        source.plan = target.plan
        source.isRest = target.isRest
        target.plan = sourcePlan
        target.isRest = sourceRest
        try? context.save()
    }

    static func today(in days: [WorkoutDay], now: Date = Date()) -> WorkoutDay? {
        let index = Weekday.index(of: now)
        return days.first { $0.weekday == index }
    }

    /// The next training day after today, with its date.
    static func nextTrainingDay(in days: [WorkoutDay], after now: Date = Date(), calendar: Calendar = .prime) -> (day: WorkoutDay, date: Date)? {
        let start = calendar.startOfDay(for: now)
        for offset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let index = Weekday.index(of: date, calendar: calendar)
            if let day = days.first(where: { $0.weekday == index && $0.state == .training }) { return (day, date) }
        }
        return nil
    }

    static func plannedDays(_ days: [WorkoutDay]) -> [NotificationService.PlannedDay] {
        days.compactMap { day in
            guard day.state == .training, let plan = day.plan else { return nil }
            return NotificationService.PlannedDay(weekday: day.weekday, workoutName: plan.name)
        }
    }

    // MARK: Routines

    @discardableResult
    static func duplicate(_ plan: WorkoutPlan, context: ModelContext) -> WorkoutPlan {
        let copy = WorkoutPlan(name: uniqueName(base: plan.name + " copy", context: context), notes: plan.notes, colorIndex: plan.colorIndex + 1)
        context.insert(copy)
        for entry in plan.sortedEntries {
            guard let exercise = entry.exercise else { continue }
            let item = PlannedExercise(position: entry.position, exercise: exercise, targetSets: entry.targetSets,
                                       targetReps: entry.targetReps, targetWeightKg: entry.targetWeightKg, restSeconds: entry.restSeconds)
            context.insert(item)
            item.plan = copy
        }
        try? context.save()
        return copy
    }

    static func delete(_ plan: WorkoutPlan, context: ModelContext) {
        for day in plan.days {
            day.plan = nil
        }
        context.delete(plan)
        try? context.save()
    }

    static func uniqueName(base: String, context: ModelContext) -> String {
        let names = Set(((try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? []).map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }
}

// MARK: - Split presets

enum PresetApplyMode: String, CaseIterable, Identifiable {
    /// Every day of the week follows the preset. Routines that drop off the timetable are kept.
    case replace
    /// Only days with nothing planned are filled.
    case fillEmpty

    var id: String { rawValue }
}

struct PresetPreviewDay: Identifiable {
    let weekday: Int
    let templateID: String?
    let name: String
    let muscles: [MuscleGroup]
    /// What's on this day now, if the preset would change it.
    let replacing: String?
    let keptAsIs: Bool
    var id: Int { weekday }
    var isRest: Bool { templateID == nil }
}

@MainActor
extension ScheduleService {
    static func muscles(for template: WorkoutTemplate, exercises: [String: Exercise]) -> [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for item in template.items {
            for muscle in exercises[item.slug]?.primaryMuscles ?? [] where !seen.contains(muscle) { seen.append(muscle) }
        }
        return seen
    }

    /// The week as it would look after applying, Monday first.
    static func preview(_ preset: SplitPreset, start: Int, mode: PresetApplyMode, days: [WorkoutDay], exercises: [String: Exercise]) -> [PresetPreviewDay] {
        let layout = preset.layout(startingOn: start)
        return Weekday.all.map { weekday in
            let existing = days.first { $0.weekday == weekday }
            let keep = mode == .fillEmpty && existing?.state != .unplanned && existing != nil
            if keep, let existing {
                return PresetPreviewDay(weekday: weekday, templateID: existing.plan?.sourceTemplateID ?? (existing.isRest ? nil : "existing"),
                                        name: existing.plan?.name ?? "Rest", muscles: existing.plan?.muscles ?? [], replacing: nil, keptAsIs: true)
            }
            let slot = layout[weekday] ?? nil
            let current: String? = {
                guard let existing else { return nil }
                switch existing.state {
                case .training: return existing.plan?.name
                case .rest: return slot == nil ? nil : "Rest"
                case .unplanned: return nil
                }
            }()
            if let slot, let template = WorkoutTemplate.library[slot] {
                return PresetPreviewDay(weekday: weekday, templateID: slot, name: template.name,
                                        muscles: muscles(for: template, exercises: exercises),
                                        replacing: current == template.name ? nil : current, keptAsIs: false)
            }
            return PresetPreviewDay(weekday: weekday, templateID: nil, name: "Rest", muscles: [], replacing: current, keptAsIs: false)
        }
    }

    /// Copies the preset's workouts into routines (reusing ones already made from the same template)
    /// and lays them onto the week. Never deletes routines or history.
    @discardableResult
    static func apply(_ preset: SplitPreset, start: Int, mode: PresetApplyMode, exercises: [Exercise], restSeconds: Int, context: ModelContext) -> [WorkoutPlan] {
        let bySlug = Dictionary(exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let existingPlans = (try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let week = ensureWeek(context: context)
        let layout = preset.layout(startingOn: start)
        var plansByTemplate: [String: WorkoutPlan] = [:]
        var created: [WorkoutPlan] = []

        func plan(for templateID: String) -> WorkoutPlan? {
            if let plan = plansByTemplate[templateID] { return plan }
            if let reuse = existingPlans.first(where: { $0.sourceTemplateID == templateID }) {
                plansByTemplate[templateID] = reuse
                return reuse
            }
            guard let template = WorkoutTemplate.library[templateID] else { return nil }
            let colour = (WorkoutTemplate.all.firstIndex(of: template) ?? 0) % Theme.palette.count
            let plan = WorkoutPlan(name: uniqueName(base: template.name, context: context), colorIndex: colour)
            plan.sourceTemplateID = templateID
            context.insert(plan)
            var position = 0
            for item in template.items {
                guard let exercise = bySlug[item.slug] else { continue }
                let compound = exercise.mechanic == .compound
                let entry = PlannedExercise(position: position, exercise: exercise, targetSets: item.sets, targetReps: item.reps,
                                            restSeconds: compound ? max(restSeconds, 120) : restSeconds)
                context.insert(entry)
                entry.plan = plan
                position += 1
            }
            plansByTemplate[templateID] = plan
            created.append(plan)
            return plan
        }

        for day in week {
            if mode == .fillEmpty && day.state != .unplanned { continue }
            if let slot = layout[day.weekday] ?? nil, let plan = plan(for: slot) {
                day.plan = plan
                day.isRest = false
            } else {
                day.plan = nil
                day.isRest = true
            }
        }
        try? context.save()
        return created
    }
}
