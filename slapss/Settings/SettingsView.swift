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
    /// The About banner's mesh drifts only while this window is key.
    @Environment(\.controlActiveState) private var activeState

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

    /// Menu presets for the overlay lead time, in seconds. Short on purpose
    /// (the calendar-app pattern): anything else lives under "Custom…", so a
    /// new value never has to grow this list. 15 min is Can's cap.
    private static let overlayLeadPresets: [Int] = [0, 10, 30, 60, 120, 300, 600, 900]

    /// Values the Custom stepper walks through: 5–55 s in 5 s steps, then
    /// 1–15 whole minutes.
    private static let overlayLeadCustomSteps: [Int] =
        Array(stride(from: 5, through: 55, by: 5)) + (1...15).map { $0 * 60 }

    /// Picker tag for "Custom…". Never stored.
    private static let overlayLeadCustomTag = -1

    /// Set when the user picks "Custom…" while on a preset value. Otherwise
    /// the Custom row shows only for stored values outside the presets.
    @State private var overlayLeadCustomChosen = false

    private var overlayLeadIsCustom: Bool {
        overlayLeadCustomChosen || !Self.overlayLeadPresets.contains(settings.overlayLeadTimeSeconds)
    }

    private var overlayLeadSelection: Binding<Int> {
        Binding(
            get: { overlayLeadIsCustom ? Self.overlayLeadCustomTag : settings.overlayLeadTimeSeconds },
            set: { tag in
                if tag == Self.overlayLeadCustomTag {
                    overlayLeadCustomChosen = true
                } else {
                    overlayLeadCustomChosen = false
                    settings.overlayLeadTimeSeconds = tag
                }
            }
        )
    }

    /// Moves to the next custom step above/below the stored value. The
    /// stored value itself is never snapped: a legacy value off the steps
    /// (e.g. 45 s or 90 s from the v1.8.1 text field) keeps firing exactly
    /// as before until the user touches the stepper.
    private func stepOverlayLead(up: Bool) {
        let s = settings.overlayLeadTimeSeconds
        let steps = Self.overlayLeadCustomSteps
        if let next = up ? steps.first(where: { $0 > s }) : steps.last(where: { $0 < s }) {
            // Stay in Custom when a step lands on a preset (90 s → 2 min),
            // or the row would vanish under the user's pointer.
            overlayLeadCustomChosen = true
            settings.overlayLeadTimeSeconds = next
        }
    }

    /// Full sentence for a lead time ("30 seconds before", "1 minute
    /// before", "At meeting start"). Menu items, the Custom row and the
    /// VoiceOver value all use it, so nobody gets a bare, unit-less number.
    private func overlayLeadLabel(_ s: Int) -> String {
        if s == 0 { return lm["settings.alert.early.0"] }
        if s == 60 { return lm["settings.alert.early.1min"] }
        if s % 60 != 0 { return lm.t("settings.alert.early.secondsFormat", s) }
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
                Picker(lm["settings.alert.showEarly"], selection: overlayLeadSelection) {
                    ForEach(Self.overlayLeadPresets, id: \.self) { s in
                        Text(overlayLeadLabel(s)).tag(s)
                    }
                    Divider()
                    Text(lm["settings.alert.early.custom"]).tag(Self.overlayLeadCustomTag)
                }
                .pickerStyle(.menu)
                if overlayLeadIsCustom {
                    LabeledContent(lm["settings.alert.early.customLabel"]) {
                        HStack(spacing: 6) {
                            Text(overlayLeadLabel(settings.overlayLeadTimeSeconds))
                                .monospacedDigit()
                            Stepper("") {
                                stepOverlayLead(up: true)
                            } onDecrement: {
                                stepOverlayLead(up: false)
                            }
                            .labelsHidden()
                            .accessibilityLabel(lm["settings.alert.early.customLabel"])
                            .accessibilityValue(overlayLeadLabel(settings.overlayLeadTimeSeconds))
                        }
                    }
                }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(lm["settings.alert.excludeKeywords"])
                    KeywordTokenField(
                        tokens: $settings.alertExcludedKeywords,
                        placeholder: lm["settings.alert.excludeKeywords.placeholder"]
                    )
                    .accessibilityLabel(lm["settings.alert.excludeKeywords"])
                }
                Text(lm["settings.alert.excludeKeywords.caption"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(lm["settings.section.menuBar"]) {
                Picker(lm["settings.menuBar.label"], selection: $settings.menuBarMeetingVisibility) {
                    Text(lm["general.off"]).tag(MenuBarMeetingVisibility.off)
                    Text(lm["settings.menuBar.whenClose"]).tag(MenuBarMeetingVisibility.whenClose)
                    Text(lm["settings.menuBar.allDay"]).tag(MenuBarMeetingVisibility.allDay)
                }
                .pickerStyle(.menu)
                Text(lm["settings.menuBar.caption"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: 0) {
            aboutBanner
            aboutForm
        }
    }

    /// Brand card on top of About, in the same theme-mesh surface as the
    /// popup's hero and the onboarding welcome card. Reuses the onboarding
    /// tagline, so no new strings.
    private var aboutBanner: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Slapss")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(settings.theme.accents.heroTitle)
                Text(lm["onboarding.welcome.tagline"])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(settings.theme.accents.heroTime)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .meshCard(theme: settings.theme, cornerRadius: 14, energy: 0.3, animating: activeState == .key)
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var aboutForm: some View {
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

                // Slapss claims your calendar never leaves the Mac. About is
                // where someone checks that kind of claim, so the source link
                // belongs here rather than buried in onboarding.
                LabeledContent(lm["settings.about.sourceCode"]) {
                    Button("github.com/theshiver/slapss-app") {
                        if let url = URL(string: "https://github.com/theshiver/slapss-app") {
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

/// AppKit's token field (Mail's To: field): each word becomes a removable
/// chip on Return or comma. SwiftUI has no equivalent. Tokens are written back
/// only when a token is committed or editing ends, never per keystroke, so a
/// half-typed "l" never briefly silences every meeting with an L-word.
private struct KeywordTokenField: NSViewRepresentable {
    @Binding var tokens: [String]
    let placeholder: String

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.objectValue = tokens
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        // Don't clobber text the user is still typing.
        if field.currentEditor() == nil, (field.objectValue as? [String]) != tokens {
            field.objectValue = tokens
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: KeywordTokenField
        init(parent: KeywordTokenField) { self.parent = parent }

        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            // objectValue doesn't include the new token until this returns.
            DispatchQueue.main.async { self.commit(tokenField) }
            return tokens
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTokenField { commit(field) }
        }

        /// Trims, drops empties, and de-duplicates case-insensitively,
        /// keeping the first spelling.
        private func commit(_ field: NSTokenField) {
            var seen = Set<String>()
            let cleaned = (field.objectValue as? [Any] ?? [])
                .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            if cleaned != parent.tokens { parent.tokens = cleaned }
        }
    }
}
