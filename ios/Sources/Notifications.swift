import Foundation
import UserNotifications

/// Local notifications: rest-timer completion and the daily weigh-in
/// reminder. Foreground presentation stays suppressed — the in-app rest bar
/// and Live Activity already cover the visible cases.
enum LocalNotifications {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: rest timer

    static func scheduleRestDone(at date: Date, exercise: String, nextSet: Int) {
        cancelRestDone()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "\(exercise) — set \(nextSet) is up"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "rest-done", content: content, trigger: trigger))
    }

    static func cancelRestDone() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["rest-done"])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["rest-done"])
    }

    // MARK: still sick?

    /// An open-ended break that runs long deserves a nudge — the guard
    /// against the forgotten-open-break hole. Fires once, 10 days after the
    /// break started (or tomorrow evening if it's already been longer).
    static func syncStillSick(openBreakStart: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["still-sick"])
        guard let openBreakStart else { return }
        requestAuthorization()
        let cal = Calendar.current
        let target = cal.date(byAdding: .day, value: 10, to: openBreakStart) ?? openBreakStart
        var comps = cal.dateComponents([.year, .month, .day], from: max(
            target, cal.date(byAdding: .day, value: 1, to: Date()) ?? target))
        comps.hour = 18
        comps.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "Still on a break?"
        content.body = "Your break is still open. End it in Forge when you're back — or just train, and it closes itself."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "still-sick", content: content, trigger: trigger))
    }

    // MARK: weigh-in reminder

    static func syncWeighInReminder(enabled: Bool, hour: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weigh-in"])
        guard enabled else { return }
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = "Weigh-in"
        content.body = "Hop on the scale and log it in Forge."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "weigh-in", content: content, trigger: trigger))
    }
}
