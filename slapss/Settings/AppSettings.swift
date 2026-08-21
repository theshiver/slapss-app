//
//  AppSettings.swift
//  slapss
//
//  User preferences. Persisted via UserDefaults so they survive app restarts
//  without bringing in Core Data or SwiftData.
//

import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let leadTimeMinutes = "slapss.leadTimeMinutes"
        static let alertSoundEnabled = "slapss.alertSoundEnabled"
        static let enabledEventKitCalendarIDs = "slapss.enabledEventKitCalendarIDs"
        static let enabledGraphCalendarIDs = "slapss.enabledGraphCalendarIDs"
        static let onboardingCompleted = "slapss.onboardingCompleted"
        static let showPastMeetingsToday = "slapss.showPastMeetingsToday"
        static let showReminders = "slapss.showReminders"
        static let showNextMeetingInMenuBar = "slapss.showNextMeetingInMenuBar"
        static let showAlertOnAllScreens = "slapss.showAlertOnAllScreens"
        static let authUserByCalendar = "slapss.authUserByCalendar"
        static let enableGoogleAuthUser = "slapss.enableGoogleAuthUser"
        static let overlayLeadTimeSeconds = "slapss.overlayLeadTimeSeconds"
        static let showReminderOverlay = "slapss.showReminderOverlay"
        static let onlyAcceptedMeetings = "slapss.onlyAcceptedMeetings"
        static let theme = "slapss.theme"
    }

    private let defaults: UserDefaults

    /// Lead-time notification minutes before the meeting. 0 disables.
    @Published var leadTimeMinutes: Int {
        didSet { defaults.set(leadTimeMinutes, forKey: Key.leadTimeMinutes) }
    }

    @Published var alertSoundEnabled: Bool {
        didSet { defaults.set(alertSoundEnabled, forKey: Key.alertSoundEnabled) }
    }

    /// EventKit calendar identifiers the user has opted into. Empty = all.
    @Published var enabledEventKitCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(enabledEventKitCalendarIDs), forKey: Key.enabledEventKitCalendarIDs)
        }
    }

    /// Microsoft Graph calendar identifiers the user has opted into. Empty = all.
    @Published var enabledGraphCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(enabledGraphCalendarIDs), forKey: Key.enabledGraphCalendarIDs)
        }
    }

    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    /// When true, the popover lists today's already-finished meetings under
    /// an "Earlier today" section. Default: true — the popover doubles as a
    /// quick agenda recap, and the past entries are useful at a glance.
    @Published var showPastMeetingsToday: Bool {
        didSet { defaults.set(showPastMeetingsToday, forKey: Key.showPastMeetingsToday) }
    }

    /// When true, today's incomplete reminders fold into the popover's
    /// chronological timeline alongside meetings. Default: true.
    @Published var showReminders: Bool {
        didSet { defaults.set(showReminders, forKey: Key.showReminders) }
    }

    /// When true, the menu bar status item shows the next/active meeting's
    /// title and countdown next to the icon. When false, only the icon is
    /// shown. Default: true.
    @Published var showNextMeetingInMenuBar: Bool {
        didSet { defaults.set(showNextMeetingInMenuBar, forKey: Key.showNextMeetingInMenuBar) }
    }

    /// When true, the full-screen alert is mirrored on every connected
    /// display. When false, it appears only on the primary screen. Default:
    /// false — most users have one screen and a single alert is enough.
    @Published var showAlertOnAllScreens: Bool {
        didSet { defaults.set(showAlertOnAllScreens, forKey: Key.showAlertOnAllScreens) }
    }

    /// Per-calendar Google `authuser` index. Keyed by EventKit calendar
    /// identifier. When a meeting's calendar has an entry here, a
    /// `meet.google.com` join link is opened with `?authuser=N` appended so
    /// it lands in the right Google account. Calendars without an entry open
    /// the link unmodified.
    @Published var authUserByCalendar: [String: Int] {
        didSet { defaults.set(authUserByCalendar, forKey: Key.authUserByCalendar) }
    }

    /// How many seconds before a meeting's start time the full-screen overlay
    /// fires. 0 = at the exact start. The Settings UI edits this as one of
    /// three units — at start (0), seconds (5–55, step 5), or minutes
    /// (1–15, stored as minutes × 60) — derived from this raw value via
    /// `SettingsView.overlayLeadUnit` (multiple-of-60 = minutes, else
    /// seconds). Default: 0 — preserves existing behaviour for existing
    /// users.
    @Published var overlayLeadTimeSeconds: Int {
        didSet { defaults.set(overlayLeadTimeSeconds, forKey: Key.overlayLeadTimeSeconds) }
    }

    /// When true, the full-screen overlay fires for EKReminder items at their
    /// due time, showing a Complete button instead of Join. Default: true —
    /// reminders are opt-out so users who care about them get the alert without
    /// having to discover a hidden setting.
    @Published var showReminderOverlay: Bool {
        didSet { defaults.set(showReminderOverlay, forKey: Key.showReminderOverlay) }
    }

    /// When true, the full-screen overlay only fires for meetings the user has
    /// accepted (or hasn't responded to yet). Meetings marked tentative or
    /// declined are skipped for the overlay but still shown in the agenda.
    /// Default: false — preserves existing behaviour for existing users.
    @Published var onlyAcceptedMeetings: Bool {
        didSet { defaults.set(onlyAcceptedMeetings, forKey: Key.onlyAcceptedMeetings) }
    }

    /// Master switch for the per-calendar Google `authuser` picker. Off by
    /// default — it's an advanced option only relevant to people signed into
    /// multiple Google accounts. When on, the Calendars tab surfaces the
    /// per-calendar account picker (only next to calendars detected as Google,
    /// or all calendars when none can be positively identified).
    @Published var enableGoogleAuthUser: Bool {
        didSet { defaults.set(enableGoogleAuthUser, forKey: Key.enableGoogleAuthUser) }
    }

    /// Color theme for the popover and the full-screen overlay. Default:
    /// `.sunset` — the original look, so existing users see no change.
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Default lead time = 15 minutes (the value in the spec).
        let storedLead = defaults.object(forKey: Key.leadTimeMinutes) as? Int
        self.leadTimeMinutes = storedLead ?? 15

        self.alertSoundEnabled = defaults.bool(forKey: Key.alertSoundEnabled)

        let storedEK = defaults.array(forKey: Key.enabledEventKitCalendarIDs) as? [String] ?? []
        self.enabledEventKitCalendarIDs = Set(storedEK)

        let storedGraph = defaults.array(forKey: Key.enabledGraphCalendarIDs) as? [String] ?? []
        self.enabledGraphCalendarIDs = Set(storedGraph)

        self.onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)

        // Default true. UserDefaults.bool returns false for missing keys, so
        // explicit object(forKey:) check is needed to distinguish "never set"
        // from "explicitly set to false."
        if defaults.object(forKey: Key.showPastMeetingsToday) == nil {
            self.showPastMeetingsToday = true
        } else {
            self.showPastMeetingsToday = defaults.bool(forKey: Key.showPastMeetingsToday)
        }

        if defaults.object(forKey: Key.showReminders) == nil {
            self.showReminders = true
        } else {
            self.showReminders = defaults.bool(forKey: Key.showReminders)
        }

        if defaults.object(forKey: Key.showNextMeetingInMenuBar) == nil {
            self.showNextMeetingInMenuBar = true
        } else {
            self.showNextMeetingInMenuBar = defaults.bool(forKey: Key.showNextMeetingInMenuBar)
        }

        // Defaults to false, which UserDefaults.bool already returns for a
        // missing key — no explicit object(forKey:) dance needed.
        self.showAlertOnAllScreens = defaults.bool(forKey: Key.showAlertOnAllScreens)

        let storedAuthUser = defaults.dictionary(forKey: Key.authUserByCalendar) as? [String: Int] ?? [:]
        self.authUserByCalendar = storedAuthUser

        // Defaults to false (UserDefaults.bool returns false for a missing key).
        self.enableGoogleAuthUser = defaults.bool(forKey: Key.enableGoogleAuthUser)

        // Defaults to 0 (at exact start). UserDefaults.integer returns 0 for a
        // missing key, which is exactly the legacy behaviour — no dance needed.
        self.overlayLeadTimeSeconds = defaults.integer(forKey: Key.overlayLeadTimeSeconds)

        // Default true — reminder overlay is opt-out so new users get the alert.
        if defaults.object(forKey: Key.showReminderOverlay) == nil {
            self.showReminderOverlay = true
        } else {
            self.showReminderOverlay = defaults.bool(forKey: Key.showReminderOverlay)
        }

        // Defaults to false (UserDefaults.bool returns false for a missing key)
        // so existing users keep firing overlays for tentative meetings.
        self.onlyAcceptedMeetings = defaults.bool(forKey: Key.onlyAcceptedMeetings)

        // Theme — falls back to .sunset (the original look) for missing or
        // unrecognized stored values.
        self.theme = defaults.string(forKey: Key.theme)
            .flatMap(AppTheme.init(rawValue:)) ?? .sunset
    }

    /// Effective Google `authuser` index for a meeting's calendar, honoring the
    /// `enableGoogleAuthUser` master switch. Returns nil when the feature is
    /// off or no index is configured — callers can pass the result straight to
    /// `MeetingURLOpener.open(_:authUser:)`.
    func authUser(forCalendarID calendarID: String?) -> Int? {
        guard enableGoogleAuthUser, let calendarID else { return nil }
        return authUserByCalendar[calendarID]
    }
}
