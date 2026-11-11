import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home, workouts, exercises, rankings, profile
}

struct Toast: Identifiable, Equatable {
    enum Style { case record, success, warning }
    let id = UUID()
    let title: String
    let message: String
    let style: Style
}

/// App-wide UI state: the selected tab, the workout in progress and transient banners.
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
    var showFirstWorkoutGuide = false
    /// Opens a screen in a sheet on launch (used by debug screenshot runs).
    var debugRoute: Route?

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

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thud() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
