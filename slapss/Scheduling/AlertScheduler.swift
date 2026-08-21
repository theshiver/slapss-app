//
//  AlertScheduler.swift
//  slapss
//
//  Schedules the lead-time notification and the full-screen overlay alert
//  for each upcoming meeting. Reacts to changes in the aggregator's meeting
//  list (events added, modified, cancelled) and the user's lead-time setting.
//
//  Concurrency: @MainActor — all timer fires and state mutations happen on
//  the main actor, simplifying the SwiftUI integration.
//

import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class AlertScheduler: ObservableObject {
    /// The meeting whose full-screen alert is currently visible. Drives the
    /// `OverlayWindowController`. Nil = no alert showing.
    @Published private(set) var activeAlert: MeetingEvent?

    private let overlayController = OverlayWindowController()

    /// Per-meeting timers for the lead-time notification (we keep these even
    /// though UN handles delivery — to support cancel-on-dismiss).
    private var leadTimers: [String: Timer] = [:]
    /// Per-meeting timers for the full-screen alert.
    private var startTimers: [String: Timer] = [:]
    /// Per-meeting effective start time we last scheduled against. Used to
    /// short-circuit `reschedule` when nothing relevant changed for a given
    /// meeting — without this, every aggregator emission cancelled and
    /// re-issued UN notifications for ALL upcoming meetings.
    private var scheduledEffectiveStart: [String: Date] = [:]
    /// Lead-time setting we last scheduled against. Settings change → blow
    /// away the per-meeting cache so every meeting gets a fresh schedule.
    private var scheduledLeadMinutes: Int?
    /// Overlay early-fire setting we last scheduled against. Same cache-bust
    /// logic as `scheduledLeadMinutes`.
    private var scheduledOverlayLeadSeconds: Int?
    /// Meetings the user dismissed via the full-screen alert. Never re-fired
    /// and excluded from the menu-bar label too. Published so views re-render.
    @Published private(set) var dismissedIDs: Set<String> = []

    /// Meetings the user explicitly hid from the menu bar via "Dismiss event"
    /// in the popover. Distinct from `dismissedIDs` — alerts will STILL fire
    /// for these meetings; only the menu-bar title text is suppressed.
    @Published private(set) var menuBarMutedIDs: Set<String> = []

    /// Manual "Presenting Now" mode. While on, the full-screen overlay never
    /// takes over the screen — every fire attempt is queued instead (same
    /// FIFO used for back-to-back meetings) and drained as soon as the mode
    /// is switched off. Lead-time notification banners are unaffected; only
    /// the screen-covering overlay is suppressed. Session-only by design —
    /// intentionally not persisted, so it can never be silently left on
    /// across a relaunch.
    @Published private(set) var presentingModeEnabled = false
    /// Snooze targets — the alert for this meeting should re-fire at this Date.
    private var snoozeUntil: [String: Date] = [:]

    /// FIFO of meetings whose start-time timer fired while another alert was
    /// already on screen. v1 silently dropped these — meaning back-to-back
    /// meetings could lose the second alert entirely. We now drain this queue
    /// inside `dismiss(...)` / `snooze(...)`.
    private var pendingAlerts: [MeetingEvent] = []

    /// Safety-net poll. Independent from the aggregator's 30s tick: this one
    /// catches missed start-timer fires caused by App Nap, system sleep, or
    /// the runloop being parked in an exclusive mode (menu tracking, modal
    /// session). Cheap — just walks the cached `upcomingMeetings`.
    private var watchdogTimer: Timer?

    /// Activity token returned by `ProcessInfo.beginActivity(...)`. Keeping
    /// this alive opts us out of App Nap, which was the dominant cause of
    /// one-shot start timers firing late (or not at all) when the popover
    /// was closed and the app had been idle.
    private var activityToken: NSObjectProtocol?

    private weak var aggregator: CalendarAggregator?
    private weak var settings: AppSettings?
    private weak var lm: LocalizationManager?
    private var cancellables: Set<AnyCancellable> = []
    private var attached = false
    /// Token for the NSWorkspace wake observer. Must be retained so the
    /// observer can be removed on deinit — discarding it leaks the registration.
    private var wakeObserver: NSObjectProtocol?

    deinit {
        watchdogTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Wires up Combine subscriptions to the aggregator + settings. Idempotent —
    /// safe to call multiple times (e.g. from view `.task`).
    func attach(aggregator: CalendarAggregator, settings: AppSettings, lm: LocalizationManager) {
        guard !attached else { return }
        attached = true
        self.aggregator = aggregator
        self.settings = settings
        self.lm = lm

        // @Published on @MainActor classes emits on the main thread when
        // mutated from MainActor context. We use assumeIsolated to satisfy
        // strict concurrency without spawning a Task.
        aggregator.$upcomingMeetings
            .sink { [weak self] meetings in
                MainActor.assumeIsolated {
                    self?.reschedule(for: meetings)
                }
            }
            .store(in: &cancellables)

        settings.$leadTimeMinutes
            .dropFirst() // skip the initial value — aggregator publish handles first scheduling
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let agg = self.aggregator else { return }
                    self.reschedule(for: agg.upcomingMeetings)
                }
            }
            .store(in: &cancellables)

        settings.$overlayLeadTimeSeconds
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let agg = self.aggregator else { return }
                    self.reschedule(for: agg.upcomingMeetings)
                }
            }
            .store(in: &cancellables)

        settings.$showReminderOverlay
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let agg = self.aggregator else { return }
                    // Bust the reminder schedule cache so reminders are re-evaluated
                    // with the new overlay preference immediately.
                    self.scheduledEffectiveStart = self.scheduledEffectiveStart.filter { key, _ in
                        !key.hasPrefix("reminder:")
                    }
                    self.reschedule(for: agg.upcomingMeetings)
                }
            }
            .store(in: &cancellables)

        settings.$onlyAcceptedMeetings
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let agg = self.aggregator else { return }
                    // Blow the whole cache so every meeting is re-evaluated:
                    // turning the filter on must cancel now-excluded meetings,
                    // turning it off must re-schedule them.
                    self.scheduledEffectiveStart.removeAll()
                    self.reschedule(for: agg.upcomingMeetings)
                }
            }
            .store(in: &cancellables)

        // Opt out of App Nap. In v1 the start-time `Timer.scheduledTimer`
        // silently slipped (or was skipped entirely) when the system put us
        // to sleep while the popover was closed — that was the dominant
        // cause of "the alert didn't fire while the app was running."
        // `.idleSystemSleepDisabled` would also prevent the Mac from sleeping
        // on its own; we deliberately don't pass that flag — we just want
        // App Nap off, not laptop-lid-respect off.
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Slapss schedules meeting alerts that must fire on time."
            )
        }

        // Wake from sleep → re-evaluate everything. Timers that should have
        // fired during sleep won't be retroactively delivered by AppKit, so
        // we lean on the missed-fire catch-up inside `reschedule` to surface
        // any meeting that's currently in-progress.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let agg = self.aggregator else { return }
                // Blow the schedule cache so `reschedule` doesn't short-circuit
                // — every meeting needs to be re-evaluated post-wake.
                self.scheduledEffectiveStart.removeAll()
                self.reschedule(for: agg.upcomingMeetings)
            }
        }

        // Safety-net watchdog. Fires every 20s in `.common` mode so menu
        // tracking and modal sessions don't park it. Cheap — just calls
        // `reschedule` which now includes a missed-fire catch-up branch.
        startWatchdog()
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let agg = self.aggregator else { return }
                // Don't wipe the cache here — the catch-up branch inside
                // `reschedule` looks at meeting bounds against `Date()`
                // directly and is independent of cache state.
                self.reschedule(for: agg.upcomingMeetings)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    // MARK: - Scheduling core

    private func reschedule(for meetings: [MeetingEvent]) {
        let currentIds = Set(meetings.map(\.id))
        let droppedIds = Set(scheduledEffectiveStart.keys).subtracting(currentIds)

        // Cancel timers for meetings that fell out of the window.
        for (id, timer) in leadTimers where !currentIds.contains(id) {
            timer.invalidate()
            leadTimers.removeValue(forKey: id)
        }
        for (id, timer) in startTimers where !currentIds.contains(id) {
            timer.invalidate()
            startTimers.removeValue(forKey: id)
        }
        // Cancel pending UN notifications (both meeting-lead and reminder-due)
        // for items that fell out — typically because the user completed the
        // reminder in Reminders.app or the meeting moved out of the 24h window.
        for id in droppedIds {
            let dummy = MeetingEvent(
                id: id, title: "", startDate: .distantPast, endDate: .distantPast,
                location: nil, rawDetails: "", calendarTitle: "",
                calendarColor: nil, source: .eventKit, attendees: []
            )
            NotificationManager.cancelLeadNotification(for: dummy)
            NotificationManager.cancelReminderNotification(for: dummy)
        }
        // Drop cached schedule state for items that fell out so a future
        // re-add doesn't get short-circuited.
        for id in droppedIds {
            scheduledEffectiveStart.removeValue(forKey: id)
        }
        for id in Set(snoozeUntil.keys).subtracting(currentIds) {
            snoozeUntil.removeValue(forKey: id)
        }
        // Pending alerts queued from a now-cancelled meeting shouldn't be
        // surfaced once the user dismisses the on-screen alert.
        pendingAlerts.removeAll(where: { !currentIds.contains($0.id) })

        let leadMinutes = settings?.leadTimeMinutes ?? 15
        let overlayLeadSeconds = settings?.overlayLeadTimeSeconds ?? 0
        // Lead-time or overlay-lead setting changed → invalidate the per-meeting
        // cache so every meeting re-schedules with the new offsets.
        if scheduledLeadMinutes != leadMinutes || scheduledOverlayLeadSeconds != overlayLeadSeconds {
            scheduledEffectiveStart.removeAll()
            scheduledLeadMinutes = leadMinutes
            scheduledOverlayLeadSeconds = overlayLeadSeconds
        }
        let now = Date()

        let showReminderOverlay = settings?.showReminderOverlay ?? true
        let onlyAccepted = settings?.onlyAcceptedMeetings ?? false

        for meeting in meetings {
            guard !dismissedIDs.contains(meeting.id) else { continue }

            // "Only accepted meetings" filter. When on, meetings the user
            // marked tentative or declined don't get an overlay or lead
            // notification — but they stay in the agenda list (this filter is
            // scheduler-only). Reminders have no RSVP and are never filtered.
            if onlyAccepted && !meeting.isReminder
                && (meeting.rsvp == .tentative || meeting.rsvp == .declined) {
                cancelScheduling(for: meeting)
                continue
            }

            // Effective start = original start, unless the user snoozed.
            let effectiveStart = snoozeUntil[meeting.id] ?? meeting.startDate

            // Missed-fire catch-up for meetings. Runs BEFORE the short-circuit
            // so a timer swallowed by App Nap, sleep, or a parked runloop mode
            // is still caught.
            let overlayFireDate = effectiveStart.addingTimeInterval(-Double(overlayLeadSeconds))
            if !meeting.isReminder
                && effectiveStart < meeting.endDate   // not a snooze-until-end
                && overlayFireDate <= now             // overlay should have fired by now
                && now < meeting.endDate             // meeting hasn't ended
                && activeAlert == nil
                && !pendingAlerts.contains(where: { $0.id == meeting.id })
            {
                fireMeetingStart(meeting)
                // Continue scheduling state below so any future occurrence
                // (post-snooze, post-restart) lands in the cache cleanly.
            }

            // Missed-fire catch-up for reminder overlays. Reminders have
            // startDate == endDate, so the meeting-style bounds check doesn't
            // apply. Use a 30-minute grace window: if the due time has passed
            // by more than 30 minutes the overlay is no longer useful.
            let reminderGrace: TimeInterval = 30 * 60
            if meeting.isReminder
                && showReminderOverlay
                && effectiveStart <= now
                && now < effectiveStart.addingTimeInterval(reminderGrace)
                && activeAlert == nil
                && !pendingAlerts.contains(where: { $0.id == meeting.id })
            {
                fireMeetingStart(meeting)
            }

            // Short-circuit: this item already has notifications/timers
            // scheduled against this exact effectiveStart. Skipping here is
            // what makes the aggregator's poll cheap — without it, every tick
            // cancelled and re-added UN requests for everything tracked.
            if scheduledEffectiveStart[meeting.id] == effectiveStart {
                continue
            }

            if meeting.isReminder {
                // Always schedule the UN notification at the due time.
                NotificationManager.cancelReminderNotification(for: meeting)
                let body = lm?["notification.reminderBody"] ?? "Reminder due now"
                NotificationManager.scheduleReminderNotification(for: meeting, at: effectiveStart, body: body)
                // Additionally schedule the overlay timer when the feature is on.
                if showReminderOverlay {
                    scheduleReminderStart(for: meeting, effectiveStart: effectiveStart, now: now)
                }
            } else {
                scheduleLead(for: meeting, effectiveStart: effectiveStart, leadMinutes: leadMinutes, now: now)
                scheduleStart(for: meeting, effectiveStart: effectiveStart, overlayLeadSeconds: overlayLeadSeconds, now: now)
            }
            scheduledEffectiveStart[meeting.id] = effectiveStart
        }
    }

    /// Tears down any timers, cached schedule state, and pending lead
    /// notification for a meeting we're intentionally excluding (e.g. filtered
    /// out by "only accepted meetings"). Without this, toggling the filter on
    /// at runtime would leave an already-scheduled timer alive.
    private func cancelScheduling(for meeting: MeetingEvent) {
        leadTimers[meeting.id]?.invalidate()
        leadTimers.removeValue(forKey: meeting.id)
        startTimers[meeting.id]?.invalidate()
        startTimers.removeValue(forKey: meeting.id)
        scheduledEffectiveStart.removeValue(forKey: meeting.id)
        pendingAlerts.removeAll(where: { $0.id == meeting.id })
        NotificationManager.cancelLeadNotification(for: meeting)
    }

    private func scheduleLead(for meeting: MeetingEvent, effectiveStart: Date, leadMinutes: Int, now: Date) {
        // Cancel any existing lead timer + notification (settings may have changed).
        leadTimers[meeting.id]?.invalidate()
        leadTimers.removeValue(forKey: meeting.id)
        NotificationManager.cancelLeadNotification(for: meeting)

        guard leadMinutes > 0 else { return }
        let leadFireDate = effectiveStart.addingTimeInterval(-Double(leadMinutes * 60))
        guard leadFireDate > now else { return }

        // Schedule the OS-level notification (works even if the app is unfocused).
        let body = lm?.t("notification.body", meeting.startTimeString) ?? "Starts at \(meeting.startTimeString)"
        NotificationManager.scheduleLeadNotification(for: meeting, at: leadFireDate, body: body, joinURL: meeting.joinURL)

        // Track in-process so we can cancel on dismiss/snooze.
        let interval = leadFireDate.timeIntervalSince(now)
        let meetingID = meeting.id
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.leadTimers.removeValue(forKey: meetingID)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        leadTimers[meeting.id] = timer
    }

    private func scheduleStart(for meeting: MeetingEvent, effectiveStart: Date, overlayLeadSeconds: Int, now: Date) {
        startTimers[meeting.id]?.invalidate()
        startTimers.removeValue(forKey: meeting.id)

        // snooze-until-end sets effectiveStart = endDate. With a non-zero
        // overlayLeadSeconds the adjusted fire date would fall inside the meeting
        // window, which is wrong — the user chose not to be alerted again.
        if effectiveStart >= meeting.endDate { return }

        // The overlay fires `overlayLeadSeconds` before the effective start.
        // When overlayLeadSeconds == 0 this is identical to the original behaviour.
        let overlayFireDate = effectiveStart.addingTimeInterval(-Double(overlayLeadSeconds))

        if overlayFireDate <= now {
            // Fire date is in the past — show immediately if no other alert is up
            // and the meeting hasn't ended yet.
            if activeAlert == nil && now < meeting.endDate {
                fireMeetingStart(meeting)
            }
            return
        }

        let interval = overlayFireDate.timeIntervalSince(now)
        // Build the timer manually so we can register it in `.common` mode.
        // `Timer.scheduledTimer` adds the timer in `.default` mode only,
        // which means menu tracking and modal sessions would freeze the
        // start-time fire — and crucially, on Apple Silicon the `.default`
        // mode is also more aggressively throttled while the app is in App
        // Nap. `.common` mode is the documented escape hatch.
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fireMeetingStart(meeting)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        startTimers[meeting.id] = timer
    }

    /// Schedules the overlay start timer for a reminder at its due time. No
    /// lead seconds — reminders are an instant in time (startDate == endDate),
    /// so there's no meaningful "X seconds before" concept.
    private func scheduleReminderStart(for meeting: MeetingEvent, effectiveStart: Date, now: Date) {
        startTimers[meeting.id]?.invalidate()
        startTimers.removeValue(forKey: meeting.id)

        guard effectiveStart > now else { return }

        let interval = effectiveStart.timeIntervalSince(now)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fireMeetingStart(meeting)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        startTimers[meeting.id] = timer
    }

    private func fireMeetingStart(_ meeting: MeetingEvent) {
        startTimers.removeValue(forKey: meeting.id)
        // Already dismissed by the user (e.g. they clicked dismiss on the
        // lead-time notification action) — don't surface.
        if dismissedIDs.contains(meeting.id) { return }

        // Presenting Now is on — never take over the screen. Queue this
        // meeting the same way we queue a back-to-back overlap, so it's
        // still surfaced (subject to the pending-queue's own end-time check)
        // as soon as the user turns presenting mode off.
        if presentingModeEnabled {
            if !pendingAlerts.contains(where: { $0.id == meeting.id }) {
                pendingAlerts.append(meeting)
            }
            return
        }

        if meeting.isReminder {
            // Reminders have startDate == endDate. Use a 30-minute grace
            // window: fire if we're within 30 minutes of the due time; skip
            // if the overlay would be stale (e.g. missed while the Mac slept).
            let gracePeriod: TimeInterval = 30 * 60
            if Date() > meeting.startDate.addingTimeInterval(gracePeriod) { return }
        } else {
            // Meetings: fire only if still within the meeting window AND the
            // start wasn't missed by more than the staleness grace. The window
            // check alone let a long meeting whose start was missed hours ago
            // (e.g. the Mac slept overnight) still fire a stale overlay on wake
            // — and back-to-back stale ones flooded the screen every morning.
            // Grace is measured from the effective start so a legitimate snooze
            // re-fire isn't suppressed.
            let stalenessGrace: TimeInterval = 10 * 60
            let effectiveStart = snoozeUntil[meeting.id] ?? meeting.startDate
            let now = Date()
            if now >= meeting.endDate { return }
            if now > effectiveStart.addingTimeInterval(stalenessGrace) { return }
        }
        // If another alert is already showing, queue it so we don't lose
        // back-to-back meetings. v1 silently returned here, and that was the
        // failure mode for adjacent 10:00 → 10:15 → 10:30 stand-up stacks.
        if activeAlert != nil {
            if !pendingAlerts.contains(where: { $0.id == meeting.id }) {
                pendingAlerts.append(meeting)
            }
            return
        }
        activeAlert = meeting

        // Play the system alert sound when the full-screen overlay fires.
        // `NSSound.beep()` respects the user's chosen alert sound in
        // System Settings → Sound → Alert sound, so we don't need to bundle
        // our own audio asset. Gated on `alertSoundEnabled` (default: off).
        if settings?.alertSoundEnabled == true {
            NSSound.beep()
        }

        guard let lm else { return }
        overlayController.show(
            meeting: meeting,
            onJoin: { [weak self] in self?.handleJoin(meeting) },
            onComplete: meeting.isReminder ? { [weak self] in self?.completeReminder(meeting) } : nil,
            onDismiss: { [weak self] in self?.dismiss(meeting) },
            onSnoozeMinutes: { [weak self] minutes in self?.snooze(meeting, minutes: minutes) },
            onSnoozeUntilEnd: { [weak self] in self?.snoozeUntilEnd(meeting) },
            mirrorOnAllScreens: settings?.showAlertOnAllScreens ?? false,
            lm: lm,
            theme: settings?.theme ?? .sunset
        )
    }

    // MARK: - User actions

    /// Marks the reminder as complete in the EventKit store, then dismisses
    /// the overlay. The EKEventStoreChanged notification that follows the save
    /// will trigger a CalendarAggregator refresh, removing the reminder from
    /// the upcoming list automatically.
    func completeReminder(_ meeting: MeetingEvent) {
        aggregator?.completeReminder(meetingEventID: meeting.id)
        dismiss(meeting)
    }

    func handleJoin(_ meeting: MeetingEvent) {
        if let url = meeting.joinURL {
            let authUser = settings?.authUser(forCalendarID: meeting.calendarID)
            MeetingURLOpener.open(url, authUser: authUser)
        }
        dismiss(meeting)
    }


    func dismiss(_ meeting: MeetingEvent) {
        dismissedIDs.insert(meeting.id)
        leadTimers[meeting.id]?.invalidate()
        leadTimers.removeValue(forKey: meeting.id)
        startTimers[meeting.id]?.invalidate()
        startTimers.removeValue(forKey: meeting.id)
        snoozeUntil.removeValue(forKey: meeting.id)
        pendingAlerts.removeAll(where: { $0.id == meeting.id })
        NotificationManager.cancelLeadNotification(for: meeting)

        if activeAlert?.id == meeting.id {
            activeAlert = nil
            overlayController.hide()
            drainPendingAlerts()
        }
    }

    func snooze(_ meeting: MeetingEvent, minutes: Int) {
        let fireDate = Date().addingTimeInterval(Double(minutes * 60))
        snoozeUntil[meeting.id] = fireDate
        // The snoozed meeting shouldn't sit in the pending queue anymore —
        // its next fire is governed by the new effectiveStart.
        pendingAlerts.removeAll(where: { $0.id == meeting.id })

        if activeAlert?.id == meeting.id {
            activeAlert = nil
            overlayController.hide()
            drainPendingAlerts()
        }

        // Re-schedule using the new effective start time.
        if let aggregator {
            reschedule(for: aggregator.upcomingMeetings)
        }
    }

    /// Show the next queued alert (if any) once the current one is dismissed.
    /// Pendings whose meeting window has already passed are skipped — by the
    /// time the user finally clears the on-screen alert, an entry queued 20
    /// minutes ago may no longer be relevant.
    private func drainPendingAlerts() {
        let now = Date()
        while let next = pendingAlerts.first {
            pendingAlerts.removeFirst()
            if dismissedIDs.contains(next.id) { continue }
            if now >= next.endDate { continue }
            fireMeetingStart(next)
            return
        }
    }

    /// Hide a single meeting from the menu-bar title label. Doesn't affect
    /// alerts — the full-screen reminder will still fire at meeting time.
    func muteFromMenuBar(_ meetingID: String) {
        menuBarMutedIDs.insert(meetingID)
    }

    /// Flips Presenting Now on/off. Turning it off immediately drains any
    /// alert that was queued while it was on (if nothing else is currently
    /// showing) rather than waiting for the next watchdog tick.
    func togglePresentingMode() {
        presentingModeEnabled.toggle()
        if !presentingModeEnabled && activeAlert == nil {
            drainPendingAlerts()
        }
    }

    /// The meeting that should drive the menu bar label and the popover's
    /// "Dismiss event" link. Skips menu-bar muted entries.
    ///
    /// Priority order (first matching wins):
    ///   1. A meeting starting within the next 5 minutes — even if another
    ///      meeting is technically still running. The user is preparing for
    ///      the imminent one and that's what should be visible. So at 11:05
    ///      with a 10:55–11:25 meeting active and a 11:10–11:40 one coming
    ///      up, the menu bar already shows the 11:10 meeting.
    ///   2. Among active (in-progress) meetings, the one that started most
    ///      recently. Overlap case where neither meeting is "imminent": the
    ///      freshly-started one wins over the trailing older one.
    ///   3. Otherwise the soonest imminent meeting (5–15 minutes away).
    ///
    /// Note: alert-dismissed meetings (`dismissedIDs`) are intentionally NOT
    /// filtered out here. Dismissing the full-screen overlay only stops the
    /// alert from re-firing — the meeting is still on the user's calendar
    /// and the title stays in the menu bar label until it ends. To clear the
    /// label specifically, the user uses the "Hide from menu bar" link in
    /// the popover, which sets `menuBarMutedIDs`.
    func currentMenuBarMeeting(now: Date = Date()) -> MeetingEvent? {
        priorityMeeting(now: now, includeReminders: true, respectMutes: true)
    }

    /// Shared promotion logic behind both the menu-bar label and the popover's
    /// hero card, so the two never disagree about which meeting is "current."
    ///
    /// - `includeReminders`: when false, reminders are excluded from the pool.
    ///   The hero card is meeting-only, so it passes false.
    /// - `respectMutes`: when false, "hidden from menu bar" entries are still
    ///   considered. Muting is a menu-bar-only concern; the popover hero
    ///   ignores it (it passes false) so the card keeps surfacing the meeting.
    ///
    /// Priority order (first matching wins) is documented in the comment block
    /// on `currentMenuBarMeeting` directly above.
    func priorityMeeting(
        now: Date = Date(),
        includeReminders: Bool,
        respectMutes: Bool
    ) -> MeetingEvent? {
        guard let aggregator else { return nil }
        // Pool: future-relevant items + (optionally) past-today reminders.
        // Reminders have startDate == endDate, so once their due time passes
        // they fall into `pastMeetingsToday`. For the menu bar we still want
        // overdue items visible — they're "due now / due X min ago" prompts
        // until the user completes them or mutes them via the popover.
        let overdueReminders = includeReminders
            ? aggregator.pastMeetingsToday.filter { $0.isReminder }
            : []
        let pool = (aggregator.upcomingMeetings + overdueReminders).filter {
            if !includeReminders && $0.isReminder { return false }
            if respectMutes && menuBarMutedIDs.contains($0.id) { return false }
            return true
        }

        // 1) About-to-start (≤ 5 min). Highest priority — preempts active
        // meetings so the user pivots to the next thing in time. Applies to
        // both events and reminders.
        let aboutToStart = pool
            .filter {
                let untilStart = $0.startDate.timeIntervalSince(now)
                return untilStart >= 0 && untilStart <= 5 * 60
            }
            .min(by: { $0.startDate < $1.startDate })
        if let aboutToStart { return aboutToStart }

        // 2) Currently relevant: events whose run-window contains `now`, and
        // reminders whose due time is in the past today (still pending).
        // Pick the one that started/became-due most recently — same "freshly
        // started wins over trailing" logic as the meeting overlap case.
        let relevant = pool.filter { item in
            if item.isReminder {
                return item.startDate <= now
            } else {
                return item.startDate <= now && now < item.endDate
            }
        }
        if let mostRecent = relevant.max(by: { $0.startDate < $1.startDate }) {
            return mostRecent
        }

        // 3) Soonest imminent (5–15 min away).
        let imminent = pool.filter {
            let untilStart = $0.startDate.timeIntervalSince(now)
            return untilStart > 5 * 60 && untilStart <= 15 * 60
        }
        return imminent.min(by: { $0.startDate < $1.startDate })
    }

    /// "Until end of meeting" — push the snooze target past the event end so
    /// `scheduleStart` filters it out and the alert never re-fires for this
    /// occurrence. Effectively a polite dismiss.
    func snoozeUntilEnd(_ meeting: MeetingEvent) {
        snoozeUntil[meeting.id] = meeting.endDate
        pendingAlerts.removeAll(where: { $0.id == meeting.id })

        if activeAlert?.id == meeting.id {
            activeAlert = nil
            overlayController.hide()
            drainPendingAlerts()
        }

        if let aggregator {
            reschedule(for: aggregator.upcomingMeetings)
        }
    }
}
