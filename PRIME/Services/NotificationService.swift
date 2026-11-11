import Foundation
import UserNotifications

/// All local notifications. Nothing is sent unless the user switched that kind on.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let restID = "prime.rest"
    private let scheduledPrefix = "prime.scheduled."
    private let missedPrefix = "prime.missed."
    private let recordPrefix = "prime.record."

    func activate() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Rest timer

    func scheduleRestTimer(endsAt: Date, label: String) {
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = label.isEmpty ? "Time for your next set." : "Next set of \(label) is up."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: content, trigger: trigger))
    }

    func cancelRestTimer() {
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        center.removeDeliveredNotifications(withIdentifiers: [restID])
    }

    // MARK: Records

    func postRecordsSummary(count: Int, workoutName: String) {
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "New personal record" : "\(count) new personal records"
        content.body = "Set during \(workoutName). Open PRIME to see them."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: recordPrefix + UUID().uuidString, content: content, trigger: trigger))
    }

    // MARK: Schedule

    struct PlannedDay: Equatable {
        let weekday: Int
        let workoutName: String
    }

    struct SchedulePreferences: Equatable {
        var scheduled: Bool
        var missed: Bool
        var scheduledMinutes: Int
        var missedMinutes: Int
    }

    /// Rebuilds the weekly reminders. Missed-workout nudges are one-off notifications for the
    /// next seven days, and today's is skipped once a workout has been logged.
    func refreshSchedule(days: [PlannedDay], preferences: SchedulePreferences, trainedToday: Bool, now: Date = Date()) {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(self.scheduledPrefix) || $0.hasPrefix(self.missedPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)

            if preferences.scheduled {
                for day in days {
                    var components = DateComponents()
                    components.weekday = Weekday.appleWeekday(for: day.weekday)
                    components.hour = preferences.scheduledMinutes / 60
                    components.minute = preferences.scheduledMinutes % 60
                    let content = UNMutableNotificationContent()
                    content.title = "Today: \(day.workoutName)"
                    content.body = "Your workout is planned for today."
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    self.center.add(UNNotificationRequest(identifier: self.scheduledPrefix + "\(day.weekday)", content: content, trigger: trigger))
                }
            }

            if preferences.missed {
                let calendar = Calendar.prime
                for offset in 0..<7 {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
                    let index = Weekday.index(of: date, calendar: calendar)
                    guard let day = days.first(where: { $0.weekday == index }) else { continue }
                    if offset == 0 && trainedToday { continue }
                    guard let fire = calendar.date(byAdding: .minute, value: preferences.missedMinutes, to: date), fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "\(day.workoutName) is still waiting"
                    content.body = "There's still time to get it done today."
                    content.sound = .default
                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let id = self.missedPrefix + String(Int(fire.timeIntervalSince1970))
                    self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
