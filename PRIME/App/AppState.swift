import Foundation
import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case home, workouts, exercises, rankings, profile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .workouts: return "Workouts"
        case .exercises: return "Exercises"
        case .rankings: return "Rankings"
        case .profile: return "Profile"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .workouts: return "calendar"
        case .exercises: return "dumbbell"
        case .rankings: return "shield.lefthalf.filled"
        case .profile: return "person.crop.circle"
        }
    }
    var selectedSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .workouts: return "calendar"
        case .exercises: return "dumbbell.fill"
        case .rankings: return "shield.lefthalf.filled"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case record, success, warning }
    let id = UUID()
    let title: String
    let message: String
    let style: Style
}

/// A request to log a ranked performance, optionally for a specific exercise.
struct RankEntryRequest: Identifiable {
    let id = UUID()
    let exerciseSlug: String?
}

/// A technique guide to show in a sheet, by exercise slug.
struct GuideRequest: Identifiable {
    let id: String
}

/// App-wide UI state: tabs, the workout in progress, sheets and transient banners.
@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    /// The workout in progress. Drives the minimised bar and start/resume logic.
    var activeSession: WorkoutSession?
    /// What the full-screen workout shows. Cleared only after it has animated away,
    /// so the screen never reads a workout that was just discarded.
    var coverSession: WorkoutSession?
    var isWorkoutPresented = false
    var finishedSummary: WorkoutSummary?
    var toast: Toast?
    var showSplitPresets = false
    var showSearch = false
    var rankEntry: RankEntryRequest?
    var reveal: RankReveal?
    var guideRequest: GuideRequest?
    /// Debug screenshots open the reveal at a fixed stage.
    var revealStage: RankRevealView.Stage = .analysis
    var revealFrozen = false
    /// Opens a screen in a sheet on launch (used by debug screenshot runs).
    var debugRoute: Route?
    /// A screen to push on the Rankings tab (e.g. after a reveal).
    var pendingRoute: Route?

    private var toastTask: Task<Void, Never>?

    func show(_ toast: Toast, for seconds: Double = 2.8) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.toast = toast }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func restoreActiveSession(context: ModelContext, now: Date = Date()) {
        guard let session = WorkoutService.activeSession(in: context) else {
            activeSession = nil
            return
        }
        activeSession = session
        coverSession = session
        // Reopen straight into a workout that was interrupted recently.
        if now.timeIntervalSince(session.startedAt) < 12 * 3600 { isWorkoutPresented = true }
    }

    func begin(_ session: WorkoutSession) {
        activeSession = session
        coverSession = session
        isWorkoutPresented = true
    }

    func endWorkout(summary: WorkoutSummary?) {
        activeSession = nil
        isWorkoutPresented = false
        // Present the summary once the full-screen workout has finished dismissing.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.coverSession = nil
            if let summary { self?.finishedSummary = summary }
        }
    }

    /// Closes the workout screen first, then deletes the session once nothing is showing it.
    func discardWorkout(_ session: WorkoutSession, context: ModelContext) {
        activeSession = nil
        isWorkoutPresented = false
        NotificationService.shared.cancelRestTimer()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.coverSession = nil
            WorkoutService.discard(session, context: context)
        }
    }

    /// Starts a workout, or reopens the one already in progress.
    func startWorkout(plan: WorkoutPlan?, context: ModelContext, store: TrainingStore) {
        guard ensureNoActiveWorkout() else { return }
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        Haptics.thud()
        begin(session)
    }

    func startWorkout(with exercise: Exercise, restSeconds: Int, context: ModelContext, store: TrainingStore) {
        guard ensureNoActiveWorkout() else { return }
        let session = WorkoutService.start(exercise: exercise, restSeconds: restSeconds, context: context, history: store.history)
        Haptics.thud()
        begin(session)
    }

    private func ensureNoActiveWorkout() -> Bool {
        guard activeSession != nil else { return true }
        isWorkoutPresented = true
        show(Toast(title: "Workout already running", message: "Finish or discard it before starting another.", style: .warning))
        return false
    }

    /// Re-syncs scheduled reminders with the timetable and preferences.
    func refreshNotifications(context: ModelContext, history: TrainingHistory, now: Date = Date()) {
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else { return }
        let days = ScheduleService.ensureWeek(context: context)
        let calendar = Calendar.prime
        let trainedToday = history.sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: now) }
        NotificationService.shared.refreshSchedule(
            days: ScheduleService.plannedDays(days),
            preferences: .init(scheduled: profile.notifyScheduledWorkouts, missed: profile.notifyMissedWorkouts,
                               scheduledMinutes: profile.scheduledReminderMinutes, missedMinutes: profile.missedReminderMinutes),
            trainedToday: trainedToday,
            now: now
        )
    }
}
