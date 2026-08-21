//
//  EventKitSource.swift
//  slapss
//
//  Reads calendar events from the user's macOS Calendar via EventKit. Covers
//  iCloud, Google (via Calendar.app sync), Exchange-via-CalDAV, and any other
//  account the user added to Calendar.app.
//

import EventKit
import Foundation

@MainActor
final class EventKitSource {
    enum AccessState {
        case notDetermined
        case denied
        case restricted
        case granted
    }

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    /// Set of EKCalendar identifiers the user opted into. Empty = all.
    var enabledCalendarIdentifiers: Set<String> = []

    /// Called when the underlying store reports a change so the aggregator
    /// can re-fetch.
    var onChange: (() -> Void)?

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    // MARK: - Permissions

    var accessState: AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess, .writeOnly, .authorized: return .granted
        @unknown default: return .denied
        }
    }

    /// Reminders use a separate authorization scope. Granting calendar access
    /// does NOT grant reminder access — they're tracked independently in
    /// macOS's Privacy & Security settings.
    var reminderAccessState: AccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess, .writeOnly, .authorized: return .granted
        @unknown default: return .denied
        }
    }

    /// Requests full read access. macOS 14+ uses `requestFullAccessToEvents`.
    /// Falls back to deprecated `requestAccess` for older systems.
    func requestAccess() async -> AccessState {
        do {
            if #available(macOS 14.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }
        } catch {
            // Treat any error as denial — user can re-grant in System Settings.
            return .denied
        }
        startObservingChanges()
        return accessState
    }

    /// Companion to `requestAccess()` for the reminders scope.
    func requestReminderAccess() async -> AccessState {
        do {
            if #available(macOS 14.0, *) {
                _ = try await store.requestFullAccessToReminders()
            } else {
                _ = try await store.requestAccess(to: .reminder)
            }
        } catch {
            return .denied
        }
        // Either scope being granted is enough to wire up the change
        // observer — `EKEventStoreChanged` fires for both event and reminder
        // mutations once the store is being used.
        startObservingChanges()
        return reminderAccessState
    }

    /// Idempotently registers the `EKEventStoreChanged` observer. Safe to
    /// call from any access path (calendar grant, reminder grant, or
    /// `CalendarAggregator.start()` for users whose access was granted in a
    /// prior session and never went through `requestAccess` this run).
    func ensureChangeObserver() {
        startObservingChanges()
    }

    private func startObservingChanges() {
        guard changeObserver == nil else { return }
        // queue: .main guarantees the callback runs on the main thread, which
        // corresponds to the main actor at runtime. Use assumeIsolated to make
        // that explicit to the type system without spawning a Task.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    // MARK: - Fetch

    /// All available calendars. The onboarding/settings UI calls this so the
    /// user can pick which ones to monitor.
    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Returns events from start-of-today to `now + horizon`, filtered by
    /// enabled calendars. Includes already-finished meetings from earlier
    /// today — the aggregator splits them out for the popover's "Earlier
    /// today" section. The scheduler still gets the future-only slice via
    /// `CalendarAggregator.upcomingMeetings`.
    func fetchTodayAndAhead(horizon: TimeInterval = 24 * 3600) -> [MeetingEvent] {
        let now = Date()
        let queryStart = Calendar.current.startOfDay(for: now)
        let end = now.addingTimeInterval(horizon)

        let calendars: [EKCalendar]?
        if enabledCalendarIdentifiers.isEmpty {
            calendars = nil // means "all" in EventKit's predicate
        } else {
            calendars = store.calendars(for: .event).filter {
                enabledCalendarIdentifiers.contains($0.calendarIdentifier)
            }
            if calendars?.isEmpty == true { return [] }
        }

        let predicate = store.predicateForEvents(withStart: queryStart, end: end, calendars: calendars)
        let raw = store.events(matching: predicate)

        return raw
            .filter { !$0.isAllDay }
            .map(toMeetingEvent)
            .sorted { $0.startDate < $1.startDate }
    }

    /// Returns today's incomplete reminders that have a due date, mapped to
    /// the unified `MeetingEvent` type with `kind == .reminder`. Reminders
    /// without a due date are skipped — without a moment in time we can't
    /// place them on the popover's chronological timeline.
    func fetchTodayReminders() async -> [MeetingEvent] {
        guard reminderAccessState == .granted else { return [] }
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: dayStart,
            ending: dayEnd,
            calendars: nil
        )
        let raw: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }

        return raw
            .compactMap { toMeetingEvent($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Reminder completion

    /// Marks an EKReminder as completed and saves it to the store. The
    /// `meetingEventID` must have the `"reminder:"` prefix set by
    /// `toMeetingEvent(_:EKReminder)`. No-op if the ID can't be resolved.
    func completeReminder(meetingEventID: String) throws {
        let prefix = "reminder:"
        guard meetingEventID.hasPrefix(prefix) else { return }
        let itemID = String(meetingEventID.dropFirst(prefix.count))
        guard let item = store.calendarItem(withIdentifier: itemID) as? EKReminder else { return }
        item.isCompleted = true
        try store.save(item, commit: true)
    }

    /// EKReminder → MeetingEvent. Reminders without a due date return nil so
    /// they don't pollute the timeline.
    private func toMeetingEvent(_ rem: EKReminder) -> MeetingEvent? {
        guard let due = resolveDueDate(rem) else { return nil }
        let id = "reminder:\(rem.calendarItemIdentifier)"
        return MeetingEvent(
            id: id,
            title: rem.title ?? "(Untitled reminder)",
            // Reminders are an instant in time. Equal start/end keeps them
            // out of "active" windows in the menu bar logic.
            startDate: due,
            endDate: due,
            location: nil,
            rawDetails: rem.notes ?? "",
            calendarTitle: rem.calendar?.title ?? "Reminders",
            calendarColor: colorRGBA(from: rem.calendar?.cgColor),
            source: .eventKit,
            attendees: [],
            kind: .reminder
        )
    }

    /// Reminders with hour/minute set get exact times; date-only reminders
    /// fall back to 09:00 — Apple Reminders' own default reminder time —
    /// so they sort sensibly into the "morning" of the timeline.
    private func resolveDueDate(_ rem: EKReminder) -> Date? {
        guard let comps = rem.dueDateComponents else { return nil }
        let cal = Calendar.current
        if let exact = cal.date(from: comps), comps.hour != nil || comps.minute != nil {
            return exact
        }
        // Date-only: re-anchor to 09:00 of the same calendar day.
        var anchored = comps
        anchored.hour = 9
        anchored.minute = 0
        return cal.date(from: anchored)
    }

    private func toMeetingEvent(_ ek: EKEvent) -> MeetingEvent {
        let details = [ek.notes, ek.location, ek.url?.absoluteString]
            .compactMap { $0 }
            .joined(separator: "\n")

        let attendees: [String] = (ek.attendees ?? []).compactMap { participant in
            // Prefer display name, fall back to URL (mailto:foo@bar) parsing.
            if let name = participant.name, !name.isEmpty { return name }
            let raw = participant.url.absoluteString
                .replacingOccurrences(of: "mailto:", with: "")
            return raw.isEmpty ? nil : raw
        }

        // EventKit hands every occurrence of a recurring event the SAME
        // `eventIdentifier` — today's stand-up and tomorrow's are
        // indistinguishable by identifier alone. Everything keyed by
        // `MeetingEvent.id` (dismissedIDs, snoozeUntil, menuBarMutedIDs, the
        // scheduler's effective-start cache) would then treat the whole series
        // as one item, so dismissing a single occurrence silently suppressed
        // the overlay for every future one while the menu-bar countdown — which
        // reads the aggregator directly and knows nothing about dismissal —
        // kept looking perfectly healthy.
        //
        // Qualify the id with the occurrence's start time. A detached instance
        // moved to a new time correctly becomes a new id, which is what we
        // want: it's a different slot and deserves its own alert.
        let occurrenceStamp = Int(ek.startDate.timeIntervalSince1970.rounded())

        return MeetingEvent(
            id: "ek:\(ek.eventIdentifier ?? UUID().uuidString)#\(occurrenceStamp)",
            title: ek.title ?? "(Untitled)",
            startDate: ek.startDate,
            endDate: ek.endDate,
            location: ek.location,
            rawDetails: details,
            calendarTitle: ek.calendar.title,
            calendarColor: colorRGBA(from: ek.calendar.cgColor),
            calendarID: ek.calendar.calendarIdentifier,
            source: .eventKit,
            attendees: attendees,
            rsvp: rsvp(for: ek)
        )
    }

    /// The signed-in user's RSVP for an event. EventKit exposes this via the
    /// attendee flagged `isCurrentUser`. Events with no such attendee (local
    /// calendars, personal events, events you organize) return `.unknown`,
    /// which the overlay filter always fires.
    private func rsvp(for ek: EKEvent) -> MeetingEvent.RSVP {
        guard let me = ek.attendees?.first(where: { $0.isCurrentUser }) else {
            return .unknown
        }
        switch me.participantStatus {
        case .accepted:  return .accepted
        case .tentative: return .tentative
        case .declined:  return .declined
        case .pending:   return .needsAction
        default:         return .unknown
        }
    }

    private func colorRGBA(from cgColor: CGColor?) -> MeetingEvent.ColorRGBA? {
        guard let cgColor, let components = cgColor.components, components.count >= 3 else {
            return nil
        }
        let alpha = components.count >= 4 ? components[3] : 1.0
        return MeetingEvent.ColorRGBA(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: Double(alpha)
        )
    }
}
