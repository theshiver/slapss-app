//
//  NotificationManager.swift
//  slapss
//
//  Wraps UNUserNotifications for the lead-time toast that appears N minutes
//  before a meeting starts. The full-screen alert at meeting time is handled
//  separately by OverlayWindowController.
//
//  Callers are responsible for localizing `body` text (via LocalizationManager)
//  before calling in — this type stays free of any English copy so nothing
//  here can silently bypass the app's language switcher.
//

import Foundation
import UserNotifications

enum NotificationManager {

    // MARK: - Categories / actions
    //
    // Two categories: one adds a "Join" action (meetings with a detected join
    // URL), the other has no actions (reminders, or meetings without a link).
    // Registered once at launch by AppDelegate with a localized action title.

    static let meetingCategoryJoin = "slapss.category.meetingJoin"
    static let meetingCategoryPlain = "slapss.category.meeting"
    static let joinActionID = "slapss.action.join"
    static let joinURLUserInfoKey = "slapss.joinURL"

    /// Registers the notification categories/actions. Call once at app launch
    /// (`AppDelegate.applicationDidFinishLaunching`) with the localized "Join"
    /// label. If the user switches language later, already-registered actions
    /// keep the launch-time title until the next app restart — an accepted
    /// limitation for this rarely-changed setting.
    static func registerCategories(joinActionTitle: String) {
        let joinAction = UNNotificationAction(
            identifier: joinActionID,
            title: joinActionTitle,
            options: [.foreground]
        )
        let joinCategory = UNNotificationCategory(
            identifier: meetingCategoryJoin,
            actions: [joinAction],
            intentIdentifiers: [],
            options: []
        )
        let plainCategory = UNNotificationCategory(
            identifier: meetingCategoryPlain,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([joinCategory, plainCategory])
    }

    // MARK: - Scheduling

    /// Schedules (or replaces) a local notification to fire at `fireDate`.
    /// Identifier is namespaced per-meeting so we can cancel it on dismiss/snooze.
    /// - Parameters:
    ///   - body: pre-localized notification body (e.g. "Starts at 14:00").
    ///   - joinURL: when non-nil, the notification gets a "Join" action that
    ///     opens this URL directly from the notification banner.
    static func scheduleLeadNotification(for meeting: MeetingEvent, at fireDate: Date, body: String, joinURL: URL?) {
        // Don't schedule notifications in the past — UN will fire them immediately.
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body = body
        content.sound = .default
        if let joinURL {
            content.categoryIdentifier = meetingCategoryJoin
            content.userInfo = [joinURLUserInfoKey: joinURL.absoluteString]
        } else {
            content.categoryIdentifier = meetingCategoryPlain
        }

        let interval = fireDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: meeting),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancelLeadNotification(for meeting: MeetingEvent) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: meeting)]
        )
    }

    /// Schedules a UN notification at a reminder's due time. Reminders use
    /// notification-only delivery — no full-screen overlay — because the
    /// "in your face" UX is reserved for live meetings the user could miss.
    static func scheduleReminderNotification(for reminder: MeetingEvent, at fireDate: Date, body: String) {
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = meetingCategoryPlain

        let interval = fireDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminderIdentifier(for: reminder),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancelReminderNotification(for reminder: MeetingEvent) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [reminderIdentifier(for: reminder)]
        )
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func identifier(for meeting: MeetingEvent) -> String {
        "slapss.lead.\(meeting.id)"
    }

    private static func reminderIdentifier(for reminder: MeetingEvent) -> String {
        "slapss.reminder.\(reminder.id)"
    }
}
