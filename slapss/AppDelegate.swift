//
//  AppDelegate.swift
//  slapss
//
//  Hosts AppKit-only setup: notification permissions and the OAuth callback
//  URL hook.
//

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()

        // Set ourselves as delegate so notifications can appear while the app
        // is active (e.g. when the menu bar popover is open). Without this,
        // macOS silently suppresses foreground notifications.
        center.delegate = self

        // Request permission upfront. Failures are non-fatal — the user can
        // still use the app, they just won't get lead-time toasts.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Register the "Join" notification action. Uses a standalone
        // LocalizationManager instance (cheap — just reads the persisted
        // language from UserDefaults) rather than the SwiftUI-owned one,
        // since AppDelegate launches before any View's environment exists.
        // If the user switches language mid-session, this label keeps its
        // launch-time value until the next app restart.
        let lm = LocalizationManager()
        NotificationManager.registerCategories(joinActionTitle: lm["popover.join"])

        // Wire up the right-click context menu on the menu bar status item.
        // Must be called after the app finishes launching so MenuBarExtra has
        // had time to register its NSStatusItem with the system status bar.
        StatusMenuController.shared.setup()
    }

    /// Handles the OAuth callback URL (msauth.com.cancetin.slapss://auth).
    /// ASWebAuthenticationSession captures its own redirect internally, so
    /// this is only called if the system routes the URL here directly (e.g.
    /// if the user somehow triggers the scheme outside the auth flow).
    func application(_ application: NSApplication, open urls: [URL]) {
        // No-op: ASWebAuthenticationSession handles the redirect internally.
        // Keeping this method ensures the URL scheme is wired to the app
        // delegate, which is required for the scheme to be recognized.
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Called when a notification is about to be presented while the app is
    /// in the foreground. We show the banner + play the sound so the user
    /// still gets the lead-time nudge even if the popover is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a delivered notification or one of its
    /// actions. The "Join" action (see `NotificationManager.registerCategories`)
    /// carries the meeting's join URL in `userInfo` — open it directly rather
    /// than just bringing the app forward. A plain tap on the banner body
    /// stays a no-op (the full-screen alert, not the banner, is the primary
    /// meeting-time surface).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == NotificationManager.joinActionID,
           let urlString = response.notification.request.content.userInfo[NotificationManager.joinURLUserInfoKey] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in
                MeetingURLOpener.open(url)
            }
        }
        completionHandler()
    }
}
