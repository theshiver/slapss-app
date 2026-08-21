//
//  MeetingEvent.swift
//  slapss
//
//  Unified meeting model. Sources (EventKit, Graph) project their native
//  events onto this type so the rest of the app works in one currency.
//

import Foundation

struct MeetingEvent: Identifiable, Hashable {
    /// Stable identity across refreshes. EventKit uses `eventIdentifier`,
    /// Graph uses the event's `id`, reminders use the EKReminder identifier.
    /// Prefix with the source/kind so collisions across sources are impossible.
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    /// Raw text fields the link detector may scan (notes/body, location, URL).
    let rawDetails: String
    let calendarTitle: String
    let calendarColor: ColorRGBA?
    /// Stable identifier of the originating calendar. Set for EventKit calendar
    /// events (`EKCalendar.calendarIdentifier`); nil for reminders and Graph
    /// events. Used to look up per-calendar preferences such as the Google
    /// `authuser` index. Defaults to nil so existing call sites stay valid.
    var calendarID: String? = nil
    let source: Source
    /// Attendee display names (or email addresses if name not available).
    /// Used for the avatar stack on the alert UI.
    let attendees: [String]
    /// Distinguishes calendar events from reminders. Defaults to `.meeting`
    /// so existing call sites (and stored snapshots) stay valid.
    var kind: Kind = .meeting

    /// The current user's RSVP response for this event, when the source
    /// exposes it. Consumed by the optional "only accepted meetings" overlay
    /// filter in `AlertScheduler`. Defaults to `.unknown` so sources and paths
    /// that don't set it (reminders, local calendars, dummy snapshots) are
    /// never filtered out.
    var rsvp: RSVP = .unknown

    enum Source: String, Hashable {
        case eventKit
        case graph
    }

    /// Current user's response to a meeting invite. Only `.tentative` and
    /// `.declined` are treated as "not accepted" by the overlay filter;
    /// everything else (including `.needsAction` and `.unknown`) still fires.
    enum RSVP: String, Hashable {
        case accepted
        case tentative
        case declined
        /// Invited but not yet responded (Graph `notResponded`, EK `.pending`).
        case needsAction
        /// No RSVP info: organizer, personal/local event, or source didn't set it.
        case unknown
    }

    enum Kind: String, Hashable {
        /// A scheduled calendar event with a start and end time.
        case meeting
        /// An EKReminder rendered as an instant-in-time entry. `startDate`
        /// equals `endDate` (both = due date). Treated read-only by the
        /// scheduler — never fires the full-screen overlay.
        case reminder
    }

    /// Lightweight color carrier so the model stays free of AppKit/SwiftUI imports.
    struct ColorRGBA: Hashable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// Convenience predicate; reminders branch differently in scheduling and
    /// rendering paths.
    var isReminder: Bool { kind == .reminder }

    /// Raw EventKit `eventIdentifier`, extracted from `id` for calendar
    /// events only (not reminders, not Graph events). `EventKitSource`
    /// prefixes event IDs with `"ek:"` and reminder IDs with `"reminder:"` —
    /// stripping the known prefix is simpler than threading a second stored
    /// property through every source and call site for one feature.
    /// Returns nil for anything that doesn't have a native Calendar.app
    /// entry to open (reminders, Microsoft Graph events).
    var eventKitIdentifier: String? {
        guard source == .eventKit, !isReminder, id.hasPrefix("ek:") else { return nil }
        return String(id.dropFirst("ek:".count))
    }

    /// First detected meeting URL (Zoom / Teams / Meet / Webex). Computed lazily
    /// by `MeetingLinkDetector` to keep the model immutable + cheap to compare.
    /// `@MainActor` because `MeetingLinkDetector.firstURL` is MainActor-isolated
    /// (NSRegularExpression in the Xcode 26 SDK); all call sites are on the main actor.
    @MainActor
    var joinURL: URL? {
        MeetingLinkDetector.firstURL(in: rawDetails)
            ?? location.flatMap(MeetingLinkDetector.firstURL(in:))
    }
}

// MARK: - Display helpers

extension MeetingEvent {
    /// "2:00 PM – 3:00 PM" or "14:00 – 15:00" — respects the user's
    /// 12/24-hour clock preference from System Settings.
    var timeRangeString: String {
        "\(Self.timeFormatter.string(from: startDate)) – \(Self.timeFormatter.string(from: endDate))"
    }

    /// "2:00 PM" or "14:00" — respects the user's 12/24-hour preference.
    var startTimeString: String {
        Self.timeFormatter.string(from: startDate)
    }

    /// Shared short-time formatter. `.short` style honours the locale's
    /// 12/24-hour preference (set in System Settings → General → Language
    /// & Region) without requiring a hard-coded format string.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// "30m" / "1h 15m" — compact duration for list rows. Takes the active
    /// `LocalizationManager` so the hour/minute units follow the app's
    /// language switcher instead of being hardcoded English abbreviations
    /// (a gap noticed after v1.8's localization pass — everything else in
    /// the popover switched languages except this).
    func durationString(lm: LocalizationManager) -> String {
        let total = Int(endDate.timeIntervalSince(startDate) / 60)
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 && minutes > 0 { return lm.t("duration.hoursMinutes", hours, minutes) }
        if hours > 0 { return lm.t("duration.hoursOnly", hours) }
        return lm.t("duration.minutesOnly", max(1, minutes))
    }

    /// "in 12 minutes" / "starting now" / "started 3 minutes ago"
    var relativeStartString: String {
        let interval = startDate.timeIntervalSinceNow
        let minutes = Int(interval / 60)

        if minutes > 1 {
            return "starts in \(minutes) minutes"
        } else if minutes == 1 {
            return "starts in 1 minute"
        } else if minutes == 0 {
            return "starting now"
        } else if minutes == -1 {
            return "started 1 minute ago"
        } else {
            return "started \(-minutes) minutes ago"
        }
    }
}
