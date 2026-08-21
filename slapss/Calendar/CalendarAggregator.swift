//
//  CalendarAggregator.swift
//  slapss
//
//  Single source of truth for upcoming meetings. Merges EventKit + Microsoft
//  Graph into a unified, sorted stream. Sources publish change notifications
//  via `onChange`, which triggers a re-fetch.
//

import Combine
import EventKit
import Foundation

@MainActor
final class CalendarAggregator: ObservableObject {
    enum PermissionState {
        case notDetermined
        case denied
        case restricted
        case granted
    }

    @Published private(set) var permissionState: PermissionState = .notDetermined
    /// Reminders authorization is tracked separately because macOS treats
    /// it as a distinct privacy scope from calendars.
    @Published private(set) var reminderPermissionState: PermissionState = .notDetermined
    /// Future-relevant meetings (endDate > now), within the next 24 hours.
    /// This is what the scheduler subscribes to for alert timing.
    @Published private(set) var upcomingMeetings: [MeetingEvent] = []
    /// Today's meetings that have already finished (endDate <= now). Drives
    /// the popover's "Earlier today" section. Excluded from the scheduler's
    /// view so it never tries to fire alerts for past events.
    @Published private(set) var pastMeetingsToday: [MeetingEvent] = []
    @Published private(set) var availableEventKitCalendars: [EKCalendar] = []

    private struct EventKitCalendarFingerprint: Equatable {
        let identifier: String
        let title: String
        let sourceIdentifier: String
        let sourceTitle: String
        let colorComponents: [CGFloat]
    }

    private let eventKit = EventKitSource()
    let graph = GraphSource()

    private var refreshTimer: Timer?
    private var eventKitCalendarFingerprint: [EventKitCalendarFingerprint] = []
    /// Latest in-flight refresh task — cancelled when a new one starts so they
    /// don't race.
    private var refreshTask: Task<Void, Never>?
    /// Latest in-flight fast-path (EventKit-only) task — cancelled when a new
    /// one starts. Without tracking this, a 30s poll that takes > 30s to
    /// complete would accumulate concurrent tasks, each triggering a full
    /// Combine cascade when it eventually finished.
    private var refreshEventKitTask: Task<Void, Never>?
    /// Coalesces rapid-fire change notifications. EKEventStoreChanged can fire
    /// many times in quick succession during an iCloud/Exchange sync — without
    /// this we'd kick off a fresh EventKit query + Graph HTTP fetch on every
    /// burst event.
    private var refreshDebounce: Timer?
    /// Idempotency guard for `start()`. The view that hosts the popover
    /// re-runs its `.task` every time the popover opens, which previously
    /// re-triggered fetches and re-published @Published properties even when
    /// nothing had changed.
    private var didStart = false

    init() {
        eventKit.onChange = { [weak self] in
            self?.refresh()
        }
        graph.onChange = { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        refreshDebounce?.invalidate()
        refreshTask?.cancel()
        refreshEventKitTask?.cancel()
    }

    /// Called when the menu bar UI first appears. Idempotent — repeated calls
    /// (e.g. from a popover's `.task` re-running on each open) are no-ops.
    ///
    /// The persisted calendar selection is passed in so it can seed the
    /// sources' fetch filters *before* the first `refresh()`. Without this the
    /// filters default to empty (= all calendars) on every launch, so the app
    /// would alert on every calendar until the user re-toggled a checkbox —
    /// even though the saved selection (and the Settings checkboxes) were
    /// correct. See `EventKitSource.fetchTodayAndAhead` where empty means all.
    func start(
        enabledEventKitCalendars: Set<String> = [],
        enabledGraphCalendars: Set<String> = []
    ) async {
        guard !didStart else { return }
        didStart = true
        eventKit.enabledCalendarIdentifiers = enabledEventKitCalendars
        graph.enabledCalendarIDs = enabledGraphCalendars
        setPermissionStateIfChanged(mapAccessState(eventKit.accessState))
        setReminderPermissionStateIfChanged(mapAccessState(eventKit.reminderAccessState))
        // If access was granted in a previous session, `requestAccess()` is
        // never called this run — so the `EKEventStoreChanged` observer was
        // never wired up. Make sure it is, otherwise live updates (added
        // calendars, new reminders) only show up via the 30s safety-net poll.
        if permissionState == .granted || reminderPermissionState == .granted {
            eventKit.ensureChangeObserver()
        }
        if permissionState == .granted {
            syncEventKitCalendarCatalog()
            refresh()
            startRefreshTimer()
        }
    }

    func requestAccess() async {
        let state = await eventKit.requestAccess()
        setPermissionStateIfChanged(mapAccessState(state))
        if permissionState == .granted {
            syncEventKitCalendarCatalog()
            refresh()
            startRefreshTimer()
        }
    }

    /// Asks the user for the Reminders privacy scope. Independent from
    /// `requestAccess()` (which is for calendars) — granting one doesn't
    /// imply the other on macOS.
    func requestReminderAccess() async {
        let state = await eventKit.requestReminderAccess()
        setReminderPermissionStateIfChanged(mapAccessState(state))
        if reminderPermissionState == .granted {
            // We may have already had calendar data published; trigger a
            // refresh so reminders fold into the merged stream.
            refresh()
        }
    }

    /// Avoid re-publishing `permissionState` when the value hasn't changed —
    /// `@Published`'s `willSet` fires on every assignment, which cascades into
    /// SwiftUI re-renders for every observer.
    private func setPermissionStateIfChanged(_ state: PermissionState) {
        if permissionState != state { permissionState = state }
    }

    private func setReminderPermissionStateIfChanged(_ state: PermissionState) {
        if reminderPermissionState != state { reminderPermissionState = state }
    }

    /// Re-checks EventKit authorization and its calendar catalog. Settings
    /// calls this when it appears and whenever the app becomes active again,
    /// covering account and permission changes made in System Settings while
    /// Slapss stays open.
    func refreshSourcesIfNecessary() {
        let wasGranted = permissionState == .granted
        syncEventKitStateAndCatalog()

        if permissionState == .granted {
            eventKit.ensureChangeObserver()
            if refreshTimer == nil {
                startRefreshTimer()
            }
            refresh()
        } else if wasGranted {
            stopRefreshTimer()
            // Remove stale EventKit events after access is revoked. The full
            // refresh preserves any independently available Graph events.
            refresh()
        }
    }

    /// Same dedup discipline as `setPermissionStateIfChanged`. EKCalendar is
    /// a reference type and can mutate in place, so compare against a cached
    /// value fingerprint rather than the previously published objects.
    private func setAvailableCalendarsIfChanged(_ calendars: [EKCalendar]) {
        let fingerprint = calendars.map {
            EventKitCalendarFingerprint(
                identifier: $0.calendarIdentifier,
                title: $0.title,
                sourceIdentifier: $0.source.sourceIdentifier,
                sourceTitle: $0.source.title,
                colorComponents: $0.cgColor.components ?? []
            )
        }
        if eventKitCalendarFingerprint != fingerprint {
            eventKitCalendarFingerprint = fingerprint
            availableEventKitCalendars = calendars
        }
    }

    /// Update the set of EventKit calendars to monitor.
    func setEnabledEventKitCalendars(_ identifiers: Set<String>) {
        eventKit.enabledCalendarIdentifiers = identifiers
        refresh()
    }

    /// Update the set of Graph calendars to monitor.
    func setEnabledGraphCalendars(_ identifiers: Set<String>) {
        graph.enabledCalendarIDs = identifiers
        refresh()
    }

    /// Marks an EKReminder as complete. Delegates to EventKitSource; the
    /// resulting EKEventStoreChanged notification will trigger a refresh
    /// automatically, so no explicit re-fetch is needed here.
    func completeReminder(meetingEventID: String) {
        do {
            try eventKit.completeReminder(meetingEventID: meetingEventID)
        } catch {
            // Silently ignore — the reminder stays in the list until the
            // next poll catches the updated state. Not worth surfacing a UI
            // error for a simple mark-complete operation.
        }
    }

    // MARK: - Private

    /// Debounced entry point. Coalesces calls within a 300ms window so a
    /// burst of EKEventStoreChanged notifications (common during iCloud /
    /// Exchange sync) only triggers one actual fetch.
    private func refresh() {
        refreshDebounce?.invalidate()
        refreshDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performRefresh()
            }
        }
    }

    /// Full refresh — re-fetches EventKit AND Graph. Called on permission
    /// changes, source change notifications, and explicit user actions.
    /// Skips publishing if the merged lists are identical to what's already
    /// published; downstream observers (notably AlertScheduler) treat any
    /// emission as "everything changed" and do expensive work on each one.
    private func performRefresh() {
        syncEventKitStateAndCatalog()

        // Cancel any in-flight refresh so they don't trample each other.
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ek = self.permissionState == .granted
                ? self.eventKit.fetchTodayAndAhead(horizon: 24 * 3600)
                : []
            guard !Task.isCancelled else { return }
            let graphEvents = await self.graph.fetchTodayAndAhead(horizon: 24 * 3600)
            guard !Task.isCancelled else { return }
            let reminders = self.reminderPermissionState == .granted
                ? await self.eventKit.fetchTodayReminders()
                : []
            guard !Task.isCancelled else { return }
            let merged = (ek + graphEvents + reminders).sorted { $0.startDate < $1.startDate }
            self.publishSplit(merged: merged)
        }
    }

    /// Fast tick path — refreshes EventKit only and reuses the last batch of
    /// Graph events. EventKit's own `EKEventStoreChanged` notification is the
    /// real-time trigger for newly-added events; this poll exists purely as a
    /// safety net (e.g. clock drift, missed notifications) and to keep the
    /// "in-progress" flag fresh as a meeting begins/ends.
    ///
    /// CRITICAL: only reassigns published arrays when their contents actually
    /// changed. A bare reassignment fires `objectWillChange`, which makes
    /// `AlertScheduler.reschedule` re-cancel and re-schedule UN notifications
    /// for every meeting on every tick — that ran ~12 times per minute and
    /// was the dominant CPU drain in v1.
    private func refreshEventKitOnly() {
        let wasGranted = permissionState == .granted
        syncEventKitStateAndCatalog()
        guard permissionState == .granted else {
            stopRefreshTimer()
            if wasGranted {
                refresh()
            }
            return
        }
        // Cancel any in-flight fast-path task before starting a new one.
        // Without this, a poll that takes > 30s (e.g. EventKit under sync
        // pressure) would accumulate concurrent tasks — each triggering a full
        // Combine cascade when it eventually finished, causing the gradual CPU
        // increase observed over multi-day uptime.
        refreshEventKitTask?.cancel()
        refreshEventKitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ek = self.eventKit.fetchTodayAndAhead(horizon: 24 * 3600)
            guard !Task.isCancelled else { return }
            let cachedGraph = (self.upcomingMeetings + self.pastMeetingsToday).filter { $0.source == .graph }
            let reminders = self.reminderPermissionState == .granted
                ? await self.eventKit.fetchTodayReminders()
                : []
            guard !Task.isCancelled else { return }
            let merged = (ek + cachedGraph + reminders).sorted { $0.startDate < $1.startDate }
            self.publishSplit(merged: merged)
        }
    }

    /// Splits the merged-and-sorted list into upcoming (endDate > now) and
    /// already-finished-today (endDate <= now AND start is today). Publishes
    /// only the slices that actually changed.
    private func publishSplit(merged: [MeetingEvent]) {
        let now = Date()
        let cal = Calendar.current
        let upcoming = merged.filter { $0.endDate > now }
        let pastToday = merged.filter { $0.endDate <= now && cal.isDateInToday($0.startDate) }
        if upcoming != upcomingMeetings {
            upcomingMeetings = upcoming
        }
        if pastToday != pastMeetingsToday {
            pastMeetingsToday = pastToday
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        // 30-second cadence. EKEventStoreChanged handles the actual "new
        // event was added" path in real time; this timer is a safety net
        // and keeps the active/imminent computation in the menu bar fresh.
        // 5s was overkill and caused cascading reschedules — see the
        // doc-comment on `refreshEventKitOnly` above.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshEventKitOnly()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func syncEventKitStateAndCatalog() {
        setPermissionStateIfChanged(mapAccessState(eventKit.accessState))
        setReminderPermissionStateIfChanged(mapAccessState(eventKit.reminderAccessState))
        syncEventKitCalendarCatalog()
    }

    private func syncEventKitCalendarCatalog() {
        if permissionState == .granted {
            setAvailableCalendarsIfChanged(eventKit.availableCalendars())
        } else {
            setAvailableCalendarsIfChanged([])
        }
    }

    private func mapAccessState(_ state: EventKitSource.AccessState) -> PermissionState {
        switch state {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .granted: return .granted
        }
    }
}
