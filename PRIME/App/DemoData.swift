#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample data for screenshots and simulator checks. Never compiled into release builds.
/// Launch arguments: `-demo` seeds six weeks of training, `-tab <home|workouts|exercises|rankings|profile>`
/// picks a tab, `-activeWorkout` opens a workout in progress, `-route <name>` opens a screen in a sheet.
@MainActor
enum DemoData {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isRequested: Bool { arguments.contains("-demo") }

    static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func apply(context: ModelContext, store: TrainingStore, appState: AppState) {
        guard isRequested else { return }
        seed(context: context, store: store)
        switch value(after: "-tab") {
        case "workouts": appState.selectedTab = .workouts
        case "exercises": appState.selectedTab = .exercises
        case "rankings": appState.selectedTab = .rankings
        case "profile": appState.selectedTab = .profile
        default: appState.selectedTab = .home
        }
        if let route = value(after: "-route") {
            switch route {
            case "analytics": appState.debugRoute = .analytics
            case "muscleMap": appState.debugRoute = .muscleMap
            case "records": appState.debugRoute = .records
            case "calculator": appState.debugRoute = .rankCalculator
            default:
                if route.hasPrefix("rank:") { appState.debugRoute = .exerciseRank(String(route.dropFirst(5))) }
                if route.hasPrefix("exercise:") { appState.debugRoute = .exercise(String(route.dropFirst(9))) }
            }
        }
        if arguments.contains("-activeWorkout") { startWorkout(context: context, store: store, appState: appState) }
    }

    private static let baseWeights: [String: Double] = [
        "barbell-bench-press": 70, "incline-dumbbell-press": 24, "overhead-press": 45, "dumbbell-lateral-raise": 10,
        "cable-triceps-pushdown": 30, "pull-up": 0, "barbell-bent-over-row": 65, "seated-cable-row": 60, "face-pull": 20,
        "barbell-curl": 30, "hammer-curl": 14, "barbell-back-squat": 100, "romanian-deadlift": 90, "leg-press": 160,
        "leg-extension": 50, "lying-leg-curl": 40, "standing-calf-raise": 80,
    ]

    private static func seed(context: ModelContext, store: TrainingStore) {
        let profile = DataService.profile(in: context)
        guard !profile.hasCompletedOnboarding else { return }
        let calendar = Calendar.prime
        let now = Date()
        profile.name = "Jude"
        profile.weightUnit = .kg
        profile.experience = .intermediate
        profile.interests = [.strength, .muscle]
        profile.preferredWeekdays = [0, 2, 4]
        profile.weeklyGoal = 3
        profile.hasCompletedOnboarding = true
        profile.hasCreatedFirstWorkout = true

        for week in 0...6 {
            let date = calendar.date(byAdding: .day, value: -7 * (6 - week), to: now) ?? now
            DataService.logBodyweight(81.6 - Double(week) * 0.22, on: date, context: context)
        }
        store.refresh(context)

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        guard let template = PlanTemplate.all.first(where: { $0.id == "ppl" }) else { return }
        template.install(context: context, exercises: exercises, weekdays: [0, 2, 4], restSeconds: 90)
        let days = ScheduleService.ensureWeek(context: context)
        let thisWeek = calendar.startOfWeek(for: now)

        for week in 0..<6 {
            for weekday in [0, 2, 4] {
                guard let start = calendar.date(byAdding: .day, value: weekday - 7 * (5 - week), to: thisWeek),
                      let time = calendar.date(bySettingHour: 18, minute: 5 + week * 3, second: 0, of: start),
                      time < calendar.startOfDay(for: now),
                      let plan = days.first(where: { $0.weekday == weekday })?.plan else { continue }
                if week == 2 && weekday == 4 { continue } // one missed session keeps the data honest
                let session = WorkoutService.start(plan: plan, context: context, history: store.history, now: time)
                session.bodyweightKg = 81.6 - Double(week) * 0.22
                var clock = time
                for item in session.sortedExercises {
                    let base = baseWeights[item.exerciseSlug] ?? 20
                    let target = item.targetReps ?? 8
                    let sets = item.sortedSets
                    for (index, set) in sets.enumerated() {
                        clock = clock.addingTimeInterval(TimeInterval(item.restSeconds + 45))
                        if base == 0 {
                            set.weightKg = 0
                            set.reps = max(1, 6 + week / 2 - (index == sets.count - 1 ? 1 : 0))
                        } else {
                            let progressed = base * (1 + 0.025 * Double(week))
                            set.weightKg = (progressed / 2.5).rounded() * 2.5
                            set.reps = max(1, target - (index == sets.count - 1 ? 1 : 0))
                        }
                        set.isCompleted = true
                        set.completedAt = clock
                    }
                }
                session.status = .completed
                session.endedAt = clock.addingTimeInterval(120)
            }
        }
        try? context.save()
        store.refresh(context)
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: 1)
    }

    private static func startWorkout(context: ModelContext, store: TrainingStore, appState: AppState) {
        guard appState.activeSession == nil else { return }
        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let plan = plans.first else { return }
        let session = WorkoutService.start(plan: plan, context: context, history: store.history, now: Date().addingTimeInterval(-1260))
        if let item = session.sortedExercises.first {
            for set in item.sortedSets.prefix(2) {
                let suggestion = WorkoutService.suggestion(for: set, in: item, history: store.history)
                set.weightKg = (suggestion.weightKg ?? 60) + 2.5
                set.reps = suggestion.reps ?? 6
                _ = try? WorkoutService.complete(set, in: item, session: session, history: store.history, context: context)
            }
            WorkoutService.startRest(session, seconds: 120, label: item.exerciseName, notify: false)
        }
        try? context.save()
        appState.begin(session)
    }
}
#endif
