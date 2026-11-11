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

// MARK: - Starter templates

struct PlanTemplate: Identifiable {
    struct Day {
        let name: String
        let items: [(slug: String, sets: Int, reps: Int)]
    }

    let id: String
    let name: String
    let summary: String
    let days: [Day]
    let symbol: String

    static let all: [PlanTemplate] = [
        PlanTemplate(id: "fullbody", name: "Full Body", summary: "Two alternating whole-body sessions. Great for 2–3 days a week.", days: [
            Day(name: "Full Body A", items: [("barbell-back-squat", 3, 5), ("barbell-bench-press", 3, 5), ("barbell-bent-over-row", 3, 8), ("dumbbell-shoulder-press", 3, 10), ("hanging-leg-raise", 3, 10)]),
            Day(name: "Full Body B", items: [("conventional-deadlift", 3, 5), ("overhead-press", 3, 5), ("lat-pulldown", 3, 10), ("dumbbell-walking-lunge", 3, 10), ("cable-crunch", 3, 12)]),
        ], symbol: "figure.strengthtraining.traditional"),
        PlanTemplate(id: "upperlower", name: "Upper / Lower", summary: "Upper and lower body on separate days. Built for 4 days a week.", days: [
            Day(name: "Upper", items: [("barbell-bench-press", 4, 6), ("barbell-bent-over-row", 4, 8), ("overhead-press", 3, 8), ("lat-pulldown", 3, 10), ("dumbbell-bicep-curl", 3, 12), ("cable-triceps-pushdown", 3, 12)]),
            Day(name: "Lower", items: [("barbell-back-squat", 4, 6), ("romanian-deadlift", 3, 8), ("leg-press", 3, 10), ("lying-leg-curl", 3, 12), ("standing-calf-raise", 4, 12), ("hanging-leg-raise", 3, 10)]),
        ], symbol: "arrow.up.arrow.down"),
        PlanTemplate(id: "ppl", name: "Push / Pull / Legs", summary: "Pressing, pulling and legs each get their own day. Run it 3 or 6 days a week.", days: [
            Day(name: "Push", items: [("barbell-bench-press", 4, 6), ("incline-dumbbell-press", 3, 10), ("overhead-press", 3, 8), ("dumbbell-lateral-raise", 3, 15), ("cable-triceps-pushdown", 3, 12)]),
            Day(name: "Pull", items: [("pull-up", 4, 8), ("barbell-bent-over-row", 3, 8), ("seated-cable-row", 3, 10), ("face-pull", 3, 15), ("barbell-curl", 3, 10), ("hammer-curl", 3, 12)]),
            Day(name: "Legs", items: [("barbell-back-squat", 4, 6), ("romanian-deadlift", 3, 8), ("leg-press", 3, 10), ("leg-extension", 3, 12), ("lying-leg-curl", 3, 12), ("standing-calf-raise", 4, 12)]),
        ], symbol: "triangle"),
        PlanTemplate(id: "machines", name: "Machine Starter", summary: "Guided machines for learning the movements safely. 2–3 days a week.", days: [
            Day(name: "Machine Circuit", items: [("machine-chest-press", 3, 10), ("lat-pulldown", 3, 10), ("leg-press", 3, 10), ("machine-seated-row", 3, 10), ("machine-shoulder-press", 3, 10), ("seated-leg-curl", 3, 12)]),
        ], symbol: "gearshape.2.fill"),
    ]

    static func recommended(forDays count: Int, experience: ExperienceLevel) -> String {
        if experience == .new { return "machines" }
        switch count {
        case ...2: return "fullbody"
        case 3: return "ppl"
        case 4: return "upperlower"
        default: return "ppl"
        }
    }

    /// Creates the routines and lays them over the chosen weekdays in order.
    @MainActor
    @discardableResult
    func install(context: ModelContext, exercises: [Exercise], weekdays: [Int], restSeconds: Int) -> [WorkoutPlan] {
        let bySlug = Dictionary(exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var plans: [WorkoutPlan] = []
        for (dayIndex, day) in days.enumerated() {
            let plan = WorkoutPlan(name: ScheduleService.uniqueName(base: day.name, context: context), colorIndex: dayIndex)
            context.insert(plan)
            var position = 0
            for item in day.items {
                guard let exercise = bySlug[item.slug] else { continue }
                let entry = PlannedExercise(position: position, exercise: exercise, targetSets: item.sets, targetReps: item.reps,
                                            restSeconds: exercise.mechanic == .compound ? max(restSeconds, 120) : restSeconds)
                context.insert(entry)
                entry.plan = plan
                position += 1
            }
            plans.append(plan)
        }
        let week = ScheduleService.ensureWeek(context: context)
        let orderedDays = weekdays.sorted()
        if !plans.isEmpty {
            for (offset, weekday) in orderedDays.enumerated() {
                guard let day = week.first(where: { $0.weekday == weekday }) else { continue }
                day.plan = plans[offset % plans.count]
                day.isRest = false
            }
            for day in week where !orderedDays.contains(day.weekday) && day.plan == nil {
                day.isRest = !orderedDays.isEmpty
            }
        }
        try? context.save()
        return plans
    }
}
