//
//  NotificationManager.swift
//  plant-alert
//

import Foundation
import UserNotifications

/// Schedules the daily "these plants need water" digest.
///
/// A notification's text is fixed when it is scheduled, so a single repeating
/// trigger could never name the right plants. Instead the next two weeks are
/// scheduled as individual one-shot notifications and rebuilt whenever the data
/// changes — well inside the 64-pending-notification limit.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "water-digest-"
    /// How many days ahead to schedule; rebuilt on every change, so this only
    /// has to outlast a stretch of the app never being opened.
    private let horizonDays = 14

    private init() {}

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Wipes and rebuilds the digest schedule from the current plants.
    func reschedule(plants: [Plant], settings: AppSettings) async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard settings.remindersEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let active = plants.filter { !$0.isRemoved }
        guard !active.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()

        for offset in 0..<horizonDays {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: now),
                let fireDate = calendar.date(
                    bySettingHour: settings.digestHour,
                    minute: settings.digestMinute,
                    second: 0,
                    of: day
                ),
                fireDate > now
            else { continue }

            // Assumes nobody waters in the meantime; the schedule is rebuilt the
            // moment anyone does, so the stale version never survives long.
            let due = active.filter { $0.isDue(on: fireDate) }
            guard !due.isEmpty else { continue }

            let request = UNNotificationRequest(
                identifier: identifierPrefix + Self.dayKey(for: fireDate, calendar: calendar),
                content: content(for: due),
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    /// Clears everything — used when reminders are switched off.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Drops the app-icon badge once the reminder has been seen.
    func clearBadge() async {
        try? await center.setBadgeCount(0)
    }

    // MARK: - Content

    private func content(for plants: [Plant]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let sorted = plants.sorted { $0.nextWateringDate < $1.nextWateringDate }

        if let only = sorted.first, sorted.count == 1 {
            content.title = "\(only.name.isEmpty ? "A plant" : only.name) needs water"
            content.body = "About \(only.amountMl) ml."
        } else {
            content.title = "\(sorted.count) plants need water"
            let names = sorted.map { $0.name.isEmpty ? "Unnamed plant" : $0.name }
            // Keep the body to a glanceable length on the lock screen.
            if names.count > 4 {
                content.body = names.prefix(3).joined(separator: " · ") + " and \(names.count - 3) more"
            } else {
                content.body = names.joined(separator: " · ")
            }
        }

        content.sound = .default
        content.badge = NSNumber(value: sorted.count)
        return content
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension NotificationManager {
    /// Fires a notification a few seconds from now so reminder delivery can be
    /// verified without waiting for the morning.
    func sendTestNotification() async {
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Plant Alert is set up"
        content.body = "This is what your daily watering reminder will look like."
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(
                identifier: "test-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
        )
    }
}

/// Lets reminders appear as a banner while the app is open, so a test
/// notification isn't silently swallowed.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
