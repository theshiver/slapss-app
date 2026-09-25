//
//  AppSettings.swift
//  slapss
//
//  User preferences. Persisted via UserDefaults so they survive app restarts
//  without bringing in Core Data or SwiftData.
//

import Combine
import Foundation

/// How far ahead the menu bar label surfaces the next meeting.
enum MenuBarMeetingVisibility: String, CaseIterable {
    /// Never — the status item shows only the icon.
    case off
    /// While a meeting is running or is within the user's lead time
    /// (floor of 15 minutes). The behaviour every version before 2.1.0 had.
    case whenClose
    /// Any remaining meeting today, however far away.
    case allDay
}

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
        /// Legacy, read-only. Superseded by `menuBarMeetingVisibility` in
        /// 2.1.0 and migrated once in `init`. Never written again.
        static let showNextMeetingInMenuBar = "slapss.showNextMeetingInMenuBar"
        static let menuBarMeetingVisibility = "slapss.menuBarMeetingVisibility"
        static let showAlertOnAllScreens = "slapss.showAlertOnAllScreens"
        static let authUserByCalendar = "slapss.authUserByCalendar"
        static let enableGoogleAuthUser = "slapss.enableGoogleAuthUser"
        static let overlayLeadTimeSeconds = "slapss.overlayLeadTimeSeconds"
        static let showReminderOverlay = "slapss.showReminderOverlay"
        static let onlyAcceptedMeetings = "slapss.onlyAcceptedMeetings"
        static let alertExcludedKeywords = "slapss.alertExcludedKeywords"
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

    /// How far ahead the menu bar status item surfaces the next meeting's
    /// title and countdown next to the icon. `.off` shows only the icon.
    /// Default: `.whenClose` — identical to the pre-2.1.0 behaviour, so
    /// existing users see no change. Replaced the `showNextMeetingInMenuBar`
    /// bool, which is still read once in `init` to migrate.
    @Published var menuBarMeetingVisibility: MenuBarMeetingVisibility {
        didSet { defaults.set(menuBarMeetingVisibility.rawValue, forKey: Key.menuBarMeetingVisibility) }
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
    /// fires. 0 = at the exact start. The Settings UI offers a preset menu
    /// plus a Custom stepper (5–55 s, 1–15 min); see
    /// `SettingsView.overlayLeadPresets`. Values outside both lists (legacy
    /// free-typed ones) are kept as stored, never snapped. Default: 0.
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

    /// Words that switch off the full-screen alert and lead notification for
    /// meetings whose title contains them ("Lunch", "PTO"). Like
    /// `onlyAcceptedMeetings` this is scheduler-only: matching meetings stay
    /// in the popover, marked as alert-off. Default: empty.
    @Published var alertExcludedKeywords: [String] {
        didSet { defaults.set(alertExcludedKeywords, forKey: Key.alertExcludedKeywords) }
    }

    /// True when `title` contains one of `alertExcludedKeywords` at the start
    /// of a word, ignoring case and accents: "lunch" matches "Team lunch" and
    /// "Lunches", "pto" does not match "Crypto sync". Plain substring search,
    /// no regex, so nothing the user types is interpreted.
    func isAlertExcluded(title: String) -> Bool {
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let t = fold(title)
        return alertExcludedKeywords.contains { keyword in
            let k = fold(keyword.trimmingCharacters(in: .whitespaces))
            guard !k.isEmpty else { return false }
            var from = t.startIndex
            while let r = t.range(of: k, range: from..<t.endIndex) {
                if r.lowerBound == t.startIndex { return true }
                let before = t[t.index(before: r.lowerBound)]
                if !before.isLetter && !before.isNumber { return true }
                from = t.index(after: r.lowerBound)
            }
            return false
        }
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
        #if DEBUG
        // Assigned in init, so `didSet` doesn't persist it.
        if DemoMode.skipsOnboarding { self.onboardingCompleted = true }
        #endif

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

        // Menu bar visibility. New key wins; otherwise migrate the legacy
        // bool once (true → .whenClose, false → .off) so users who had turned
        // the label off keep it off. The legacy key is never written again.
        if let stored = defaults.string(forKey: Key.menuBarMeetingVisibility)
            .flatMap(MenuBarMeetingVisibility.init(rawValue:)) {
            self.menuBarMeetingVisibility = stored
        } else if defaults.object(forKey: Key.showNextMeetingInMenuBar) != nil {
            self.menuBarMeetingVisibility =
                defaults.bool(forKey: Key.showNextMeetingInMenuBar) ? .whenClose : .off
        } else {
            self.menuBarMeetingVisibility = .whenClose
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
        self.alertExcludedKeywords = defaults.stringArray(forKey: Key.alertExcludedKeywords) ?? []

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
