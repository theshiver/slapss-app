//
//  SettingsView.swift
//  slapss
//
//  Preferences window. Reachable via Cmd-, or the "Preferences…" entry in
//  the menu bar popover.
//

import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var aggregator: CalendarAggregator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lm: LocalizationManager

    @Environment(\.openWindow) private var openWindow

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(lm["settings.tab.general"], systemImage: "gearshape") }

            calendarsTab
                .tabItem { Label(lm["settings.tab.calendars"], systemImage: "calendar") }

            aboutTab
                .tabItem { Label(lm["settings.section.about"], systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
        .task {
            aggregator.refreshSourcesIfNecessary()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            aggregator.refreshSourcesIfNecessary()
        }
    }

    // MARK: - Helpers

    /// Discrete steps for the overlay lead-time slider: at meeting start,
    /// 30 seconds, then 1–15 whole minutes (15 is Can's cap for the
    /// full-screen alert). 17 detents total.
    private static let overlayLeadSteps: [Int] = [0, 30] + (1...15).map { $0 * 60 }

    /// Index of the step closest to the stored seconds value. Legacy
    /// free-typed values that don't fall on a detent (e.g. 45 s from the
    /// v1.8.1 text field) snap to the nearest step on read — no migration.
    private var overlayLeadStepIndex: Int {
        let s = settings.overlayLeadTimeSeconds
        return Self.overlayLeadSteps.indices.min {
            abs(Self.overlayLeadSteps[$0] - s) < abs(Self.overlayLeadSteps[$1] - s)
        } ?? 0
    }

    /// Slider position ↔ stored seconds. The slider moves over step
    /// *indices* (0...16), not seconds, so detents are evenly spaced even
    /// though the underlying values aren't linear (0, 30 s, 1–15 min).
    private var overlayLeadSliderValue: Binding<Double> {
        Binding(
            get: { Double(overlayLeadStepIndex) },
            set: { settings.overlayLeadTimeSeconds = Self.overlayLeadSteps[Int($0.rounded())] }
        )
    }

    /// Full sentence for the current selection ("30 seconds before",
    /// "5 minutes before", "At meeting start") — shown live next to the
    /// slider and used as the accessibility value, so neither sighted users
    /// nor VoiceOver ever get a bare, unit-less number.
    private var overlayLeadLabel: String {
        let s = Self.overlayLeadSteps[overlayLeadStepIndex]
        if s == 0 { return lm["settings.alert.early.0"] }
        if s < 60 { return lm.t("settings.alert.early.secondsFormat", s) }
        return lm.t("settings.alert.early.minutesFormat", s / 60)
    }

    /// Marketing version from the bundle (e.g. "1.6").
    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // MARK: - Tabs

    /// Inline copy that explains the current reminder authorization state
    /// when the toggle is on but EventKit hasn't been granted access.
    private var reminderPermissionMessage: String {
        switch aggregator.reminderPermissionState {
        case .notDetermined:
            return lm["settings.reminders.notDetermined"]
        case .denied, .restricted:
            return lm["settings.reminders.denied"]
        case .granted:
            return ""
        }
    }

    private var generalTab: some View {
        Form {
            Section(lm["settings.section.language"]) {
                Picker(lm["settings.language.label"], selection: Binding(
                    get: { lm.language },
                    set: { lm.setLanguage($0) }
                )) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(lm["settings.section.theme"]) {
                ThemeSwatchPicker()
            }

            Section(lm["settings.section.alert"]) {
                Picker(lm["settings.leadTime.label"], selection: $settings.leadTimeMinutes) {
                    Text(lm["general.off"]).tag(0)
                    Text(lm["settings.leadTime.1before"]).tag(1)
                    Text(lm["settings.leadTime.5before"]).tag(5)
                    Text(lm["settings.leadTime.10before"]).tag(10)
                    Text(lm["settings.leadTime.15before"]).tag(15)
                    Text(lm["settings.leadTime.30before"]).tag(30)
                }
                .pickerStyle(.menu)
                // Caption disambiguating the two adjacent "lead time"
                // controls: this one is a standard notification…
                Text(lm["settings.leadTime.caption"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent(lm["settings.alert.showEarly"]) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(overlayLeadLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Slider(
                            value: overlayLeadSliderValue,
                            in: 0...Double(Self.overlayLeadSteps.count - 1),
                            step: 1
                        )
                        .frame(width: 200)
                        .accessibilityValue(overlayLeadLabel)
                    }
                }
                .accessibilityValue(overlayLeadLabel)
                // …and this one is the full-screen takeover alert.
                Text(lm["settings.alert.showEarly.caption"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(lm["settings.alert.playSound"], isOn: $settings.alertSoundEnabled)
                Toggle(lm["settings.alert.allDisplays"], isOn: $settings.showAlertOnAllScreens)
                Toggle(lm["settings.alert.reminderOverlay"], isOn: $settings.showReminderOverlay)
                Toggle(lm["settings.alert.onlyAccepted"], isOn: $settings.onlyAcceptedMeetings)
                // The filter fails open (unknown RSVP still fires) and is
                // scheduler-only — without this line users think it's broken
                // when a tentative meeting still shows up in the agenda.
                Text(lm["settings.alert.onlyAccepted.caption"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(lm["settings.section.menuBar"]) {
                Toggle(lm["settings.menuBar.showMeeting"], isOn: $settings.showNextMeetingInMenuBar)
            }

            Section(lm["settings.section.popover"]) {
                Toggle(lm["settings.popover.showEarlier"], isOn: $settings.showPastMeetingsToday)
                Toggle(lm["settings.popover.showReminders"], isOn: $settings.showReminders)
                if settings.showReminders && aggregator.reminderPermissionState != .granted {
                    HStack(spacing: 8) {
                        Text(reminderPermissionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if aggregator.reminderPermissionState == .notDetermined {
                            Button(lm["general.continue"]) {
                                Task { await aggregator.requestReminderAccess() }
                            }
                            .controlSize(.small)
                        } else {
                            Button(lm["general.openSystemSettings"]) {
                                SystemSettingsOpener.openRemindersPrivacy()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section(lm["settings.section.googleMeet"]) {
                Toggle(lm["settings.googleMeet.perCalendar"], isOn: $settings.enableGoogleAuthUser)
                Text(lm["settings.googleMeet.description"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(lm["settings.section.startup"]) {
                Toggle(lm["settings.startup.launchAtLogin"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
            }

        }
        .formStyle(.grouped)
        .padding()
    }

    /// Split out from `generalTab` in v1.8 — the General tab had grown to 8
    /// sections crammed into a fixed-height window and scrolled awkwardly.
    /// About/version/support content doesn't relate to day-to-day settings
    /// anyway, so it gets its own tab rather than a taller window.
    private var aboutTab: some View {
        Form {
            Section(lm["settings.section.about"]) {
                LabeledContent(lm["settings.about.version"]) {
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                }

                LabeledContent(lm["settings.about.website"]) {
                    Button("slapss-app.com") {
                        if let url = URL(string: "https://www.slapss-app.com/") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }

                LabeledContent(lm["settings.about.support"]) {
                    Button("info@slapss-app.com") {
                        if let url = URL(string: "mailto:info@slapss-app.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }

                Button(lm["settings.about.tourAgain"]) {
                    settings.onboardingCompleted = false
                    // Capture Settings window BEFORE openWindow() — that call
                    // makes the new onboarding window key, so keyWindow would
                    // point to onboarding (and close it) if we wait until after.
                    let settingsWindow = NSApp.keyWindow
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                    settingsWindow?.close()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var calendarsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                eventKitSection
                Divider()
                microsoftSection
            }
            .padding()
        }
    }

    private var eventKitSection: some View {
        let calendars = aggregator.availableEventKitCalendars
        let pickerCalendarIDs = googleAuthUserCalendarIDs(in: calendars)

        return VStack(alignment: .leading, spacing: 8) {
            Text(lm["settings.calendars.macos.title"])
                .font(.headline)
            Text(lm["settings.calendars.macos.description"])
                .font(.caption)
                .foregroundStyle(.secondary)

            // Without calendar permission the ForEach below is empty and the
            // tab dead-ends (title + description, no calendars, no way
            // forward). Mirror the popover's permission states so the user
            // can grant or fix access from right here.
            switch aggregator.permissionState {
            case .notDetermined:
                Button(lm["general.continue"]) {
                    Task { await aggregator.requestAccess() }
                }
                .controlSize(.small)
            case .denied, .restricted:
                Text(lm["popover.permissionDenied"])
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(lm["popover.permissionDeniedHelp"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(lm["general.openSystemSettings"]) {
                    SystemSettingsOpener.openCalendarPrivacy()
                }
                .controlSize(.small)
            case .granted:
                EmptyView()
            }

            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: bindingForEventKit(id: calendar.calendarIdentifier)) {
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            Spacer()
                            Text(calendar.source.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if settings.enableGoogleAuthUser,
                       pickerCalendarIDs.contains(calendar.calendarIdentifier) {
                        Picker(
                            lm["settings.calendars.openMeetAs"],
                            selection: authUserBinding(id: calendar.calendarIdentifier)
                        ) {
                            Text(lm["settings.calendars.defaultAccount"]).tag(-1)
                            ForEach(0..<5) { index in
                                Text(lm.t("settings.calendars.account", index, index)).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .padding(.leading, 18)
                    }
                }
            }

            if settings.enableGoogleAuthUser {
                Text(lm["settings.calendars.authUserHint"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// Which calendars should show the Google `authuser` picker. We try to
    /// positively identify Google calendars by their EventKit source; when at
    /// least one is found, only those get the picker. When none can be
    /// identified (Google Workspace accounts on a custom domain are
    /// indistinguishable from other CalDAV sources), we fall back to offering
    /// it on every calendar so the option isn't silently unavailable.
    private func googleAuthUserCalendarIDs(in calendars: [EKCalendar]) -> Set<String> {
        let googleIDs = calendars
            .filter(isLikelyGoogleCalendar)
            .map(\.calendarIdentifier)
        if googleIDs.isEmpty {
            return Set(calendars.map(\.calendarIdentifier))
        }
        return Set(googleIDs)
    }

    /// Best-effort Google detection. EventKit has no `.google` source type, so
    /// we match on the source title: a Google account synced via Internet
    /// Accounts carries a "Google" / "gmail" / "googlemail" title (consumer
    /// accounts use the email address). Custom-domain Workspace accounts can't
    /// be told apart from generic CalDAV here and fall through to the caller's
    /// all-calendars fallback.
    private func isLikelyGoogleCalendar(_ calendar: EKCalendar) -> Bool {
        let title = calendar.source.title.lowercased()
        return title.contains("google")
            || title.contains("gmail")
            || title.contains("googlemail")
    }

    /// Per-calendar Google `authuser` index. `-1` is the sentinel for
    /// "Default account" (no `authuser` applied) — distinct from index 0,
    /// which is a real, valid first account.
    private func authUserBinding(id: String) -> Binding<Int> {
        Binding(
            get: { settings.authUserByCalendar[id] ?? -1 },
            set: { newValue in
                if newValue < 0 {
                    settings.authUserByCalendar.removeValue(forKey: id)
                } else {
                    settings.authUserByCalendar[id] = newValue
                }
            }
        )
    }

    private var microsoftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lm["settings.microsoft.title"])
                    .font(.headline)
                Spacer()
                graphActionButton
            }

            switch aggregator.graph.state {
            case .signedOut:
                Text(lm["settings.microsoft.description"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                adminHelpDisclosure

            case .signingIn:
                ProgressView(lm["settings.microsoft.signingIn"])
                    .controlSize(.small)

            case .signedIn(let displayName):
                if let displayName {
                    Text(lm.t("settings.microsoft.signedInAs", displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(aggregator.graph.availableCalendars) { calendar in
                    Toggle(isOn: bindingForGraph(id: calendar.id)) {
                        HStack {
                            Circle()
                                .fill(graphCalendarColor(calendar))
                                .frame(width: 10, height: 10)
                            Text(calendar.name)
                            if calendar.isDefaultCalendar == true {
                                Text(lm["settings.microsoft.default"])
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }

            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                adminHelpDisclosure
            }
        }
    }

    // MARK: - IT admin approval helper

    /// Some tenants block users from consenting to third-party apps and require
    /// the IT admin to pre-approve the app. Surface this case directly so users
    /// don't get stuck — they can fire off a templated email to their admin or
    /// copy a one-click admin-consent URL.
    private var adminHelpDisclosure: some View {
        DisclosureGroup(lm["settings.microsoft.adminHelp"]) {
            VStack(alignment: .leading, spacing: 8) {
                Text(lm["settings.microsoft.adminDescription"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(lm["settings.microsoft.emailAdmin"]) { openAdminEmailDraft() }
                    Button(lm["settings.microsoft.copyLink"]) { copyAdminConsentURL() }
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .font(.callout)
    }

    private func adminConsentURL() -> URL? {
        URL(string: "https://login.microsoftonline.com/organizations/adminconsent?client_id=\(MSALConfig.clientID)")
    }

    private func openAdminEmailDraft() {
        let consent = adminConsentURL()?.absoluteString ?? ""
        let subject = "Approval request: Slapss for macOS"
        let body = """
        Hi,

        I'd like to use Slapss, a macOS app that reminds me about upcoming meetings on my Mac. It needs to be approved on our tenant before I can sign in with my work account.

        What it requests:
        • Calendars.Read — read my calendar to schedule reminders
        • User.Read — display my name in the app

        It does NOT write to my calendar, send anything anywhere, or share data with any third party. All event data stays on my Mac.

        To approve it tenant-wide as an admin, sign in here in one click:
        \(consent)

        Thanks!
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyAdminConsentURL() {
        guard let url = adminConsentURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @ViewBuilder
    private var graphActionButton: some View {
        switch aggregator.graph.state {
        case .signedOut, .error:
            Button(lm["settings.microsoft.connect"]) {
                Task { await aggregator.graph.signIn() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!aggregator.graph.isConfigured)

        case .signingIn:
            EmptyView()

        case .signedIn:
            Button(lm["settings.microsoft.signOut"]) {
                Task { await aggregator.graph.signOut() }
            }
            .controlSize(.small)
        }
    }

    private func graphCalendarColor(_ calendar: GraphTypes.Calendar) -> Color {
        guard var hex = calendar.hexColor else { return .secondary }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return .secondary }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func bindingForEventKit(id: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.enabledEventKitCalendarIDs.isEmpty ||
                settings.enabledEventKitCalendarIDs.contains(id)
            },
            set: { newValue in
                if settings.enabledEventKitCalendarIDs.isEmpty {
                    let all = aggregator.availableEventKitCalendars.map(\.calendarIdentifier)
                    settings.enabledEventKitCalendarIDs = Set(all)
                }
                if newValue {
                    settings.enabledEventKitCalendarIDs.insert(id)
                } else {
                    settings.enabledEventKitCalendarIDs.remove(id)
                }
                aggregator.setEnabledEventKitCalendars(settings.enabledEventKitCalendarIDs)
            }
        )
    }

    private func bindingForGraph(id: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.enabledGraphCalendarIDs.isEmpty ||
                settings.enabledGraphCalendarIDs.contains(id)
            },
            set: { newValue in
                if settings.enabledGraphCalendarIDs.isEmpty {
                    let all = aggregator.graph.availableCalendars.map(\.id)
                    settings.enabledGraphCalendarIDs = Set(all)
                }
                if newValue {
                    settings.enabledGraphCalendarIDs.insert(id)
                } else {
                    settings.enabledGraphCalendarIDs.remove(id)
                }
                aggregator.setEnabledGraphCalendars(settings.enabledGraphCalendarIDs)
            }
        )
    }
}
