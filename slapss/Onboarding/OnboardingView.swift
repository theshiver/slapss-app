//
//  OnboardingView.swift
//  slapss
//
//  First-launch flow rendered in a standalone Window scene (not inside the
//  menu-bar popover). Walks the user through:
//    1. Language preference
//    2. Theme choice
//    3. Calendar permission (required)
//    4. Reminders permission (optional)
//    5. Microsoft 365 / Exchange sign-in (optional, if MSAL is configured)
//    6. Picking which calendars to watch (EventKit + Graph)
//    7. Lead-time choice
//    8. Launch-at-login opt-in
//
//  Visual direction follows the 2.2.0 design language shared with the popup
//  and the full-screen alert: a theme-mesh welcome card, glass step cards,
//  pill-style step numbers and the alert's gradient CTA, on a calm canvas.
//
//  Lifecycle:
//    - Opened automatically on first launch by `MenuBarLabel.task` when
//      `AppSettings.onboardingCompleted == false`.
//    - Closes itself (via `dismissWindow`) when the user clicks "Get Started",
//      after flipping `onboardingCompleted` to true.
//

import AppKit
import EventKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var aggregator: CalendarAggregator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lm: LocalizationManager

    @Environment(\.dismissWindow) private var dismissWindow

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    // MARK: - Dynamic step numbering
    //
    // The Microsoft step only renders when MSAL is configured, and the
    // calendar-picker step only after permission is granted — hardcoded
    // badge numbers therefore showed visible gaps (1,2,3,4,6,7,8 without
    // Graph). Numbers are computed from the currently visible steps instead.
    // They can shift while the window is open (e.g. the calendars step
    // appearing after permission is granted renumbers the ones below it) —
    // that's correct: the sequence the user sees is always contiguous.

    private enum StepID {
        case language, theme, calendarSources, reminders, calendars,
             leadTime, launchAtLogin
    }

    private var visibleSteps: [StepID] {
        var steps: [StepID] = [.language, .theme, .calendarSources, .reminders]
        if aggregator.hasAnyActiveSource { steps.append(.calendars) }
        steps.append(.leadTime)
        steps.append(.launchAtLogin)
        return steps
    }

    private func stepNumber(_ id: StepID) -> Int {
        (visibleSteps.firstIndex(of: id) ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    HeroStickerView()
                        .padding(.top, 24)
                        .padding(.bottom, 4)

                    VStack(spacing: 12) {
                        // 1 — language preference. Shown first so the rest
                        // of the flow renders in the user's chosen language.
                        languageStep

                        // 2 — theme choice. Early so the rest of the flow
                        // (hero sticker, badges, buttons) previews it live.
                        themeStep

                        calendarSourcesStep

                        reminderPermissionStep

                        if aggregator.hasAnyActiveSource {
                            calendarsStep
                        }
                        leadTimeStep
                        launchAtLoginStep
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }

            footerCTA
        }
        .frame(width: 480, height: 620)
        .background(Tokens.paper)
        // Cancel any inherited animation transactions — same defense the
        // popup uses, so the window doesn't pulse during data hydration.
        .transaction { txn in txn.disablesAnimations = true }
        .task {
            // Reflect any change made elsewhere (e.g. by the user toggling
            // login items in System Settings while the window is open).
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }

    // MARK: - Hero

    /// The welcome card: the same theme-mesh surface as the popup's hero,
    /// oriented for a wide window. Brand mark on the left, title and tagline
    /// on the right. It previews the theme picked in step 2 live.
    private struct HeroStickerView: View {
        @EnvironmentObject private var lm: LocalizationManager
        @EnvironmentObject private var settings: AppSettings
        /// Drift only while the window is the key window, so an onboarding
        /// window left open behind other apps doesn't keep redrawing.
        @Environment(\.controlActiveState) private var activeState

        private var accents: AppTheme.Accents { settings.theme.accents }

        var body: some View {
            HStack(alignment: .center, spacing: 20) {
                BrandStickerMark()
                VStack(alignment: .leading, spacing: 6) {
                    Text(lm["onboarding.welcome.title"])
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(accents.heroTitle)
                    Text(lm["onboarding.welcome.tagline"])
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accents.heroTime)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            .meshCard(theme: settings.theme, cornerRadius: 20, energy: 0.3,
                      animating: activeState == .key)
            .padding(.horizontal, 24)
        }
    }

    /// 56pt brand mark backed by the bundled AppIcon. The icon fills the
    /// rounded square edge-to-edge — no tinted backdrop, no border — matching
    /// the menu-bar header logo, scaled up for the welcome moment. A soft drop
    /// shadow keeps it grounded on the page.
    private struct BrandStickerMark: View {
        var body: some View {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Step 1: Language

    private var languageStep: some View {
        StepCard(number: stepNumber(.language), title: lm["onboarding.step.language.title"]) {
            Text(lm["onboarding.step.language.body"])
                .stepBody()

            Picker("", selection: Binding(
                get: { lm.language },
                set: { lm.setLanguage($0) }
            )) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    // MARK: - Step 2: Theme

    private var themeStep: some View {
        StepCard(number: stepNumber(.theme), title: lm["onboarding.step.theme.title"]) {
            Text(lm["onboarding.step.theme.body"])
                .stepBody()
            ThemeSwatchPicker()
        }
    }

    // MARK: - Step 3: Calendar sources

    private var calendarSourcesStep: some View {
        StepCard(number: stepNumber(.calendarSources), title: lm["onboarding.step.sources.title"]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(lm["onboarding.step.sources.appleTitle"])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.ink)
                    Spacer()
                    if aggregator.permissionState == .granted {
                        Toggle("", isOn: Binding(
                            get: { settings.appleCalendarEnabled },
                            set: { newValue in
                                if newValue && settings.enabledEventKitCalendarIDs == ["__none__"] {
                                    settings.enabledEventKitCalendarIDs = []
                                    aggregator.setEnabledEventKitCalendars([])
                                }
                                settings.appleCalendarEnabled = newValue
                                aggregator.setAppleCalendarEnabled(newValue)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel(lm["onboarding.step.sources.appleTitle"])
                    }
                }

                switch aggregator.permissionState {
                case .notDetermined:
                    Text(lm["onboarding.step.sources.appleBody"])
                        .stepBody()
                    PrimaryStepButton(title: lm["general.continue"]) {
                        Task { await aggregator.requestAccess() }
                    }
                case .denied, .restricted:
                    Text(lm["onboarding.step.calendarAccess.denied"])
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(lm["general.openSystemSettings"]) {
                        SystemSettingsOpener.openCalendarPrivacy()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .clickCursor()
                case .granted:
                    if settings.appleCalendarEnabled {
                        StatusBadge(text: lm["onboarding.step.calendarAccess.granted"], systemImage: "checkmark.circle.fill", tint: .green)
                    } else {
                        Text(lm["settings.calendars.macos.disabled"])
                            .stepBody()
                    }
                }
            }

            if aggregator.google.isConfigured || aggregator.graph.isConfigured {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text(lm["onboarding.step.sources.optionalHeader"])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.ink2)

                    if aggregator.google.isConfigured {
                        GoogleOnboardingRow(google: aggregator.google) {
                            settings.enabledGoogleCalendarIDs.remove("__none__")
                            aggregator.setEnabledGoogleCalendars(settings.enabledGoogleCalendarIDs)
                        }
                    }

                    if aggregator.graph.isConfigured {
                        MicrosoftOnboardingRow(graph: aggregator.graph) {
                            settings.enabledGraphCalendarIDs.remove("__none__")
                            aggregator.setEnabledGraphCalendars(settings.enabledGraphCalendarIDs)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Reminders permission

    private var reminderPermissionStep: some View {
        StepCard(number: stepNumber(.reminders), title: lm["onboarding.step.reminders.title"]) {
            switch aggregator.reminderPermissionState {
            case .notDetermined:
                Text(lm["onboarding.step.reminders.body"])
                    .stepBody()
                PrimaryStepButton(title: lm["general.continue"]) {
                    Task { await aggregator.requestReminderAccess() }
                }
            case .denied, .restricted:
                Text(lm["onboarding.step.reminders.denied"])
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(lm["general.openSystemSettings"]) {
                    SystemSettingsOpener.openRemindersPrivacy()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clickCursor()
            case .granted:
                StatusBadge(text: lm["onboarding.step.reminders.granted"], systemImage: "checkmark.circle.fill", tint: .green)
            }
        }
    }

    private struct GoogleOnboardingRow: View {
        @ObservedObject var google: GoogleSource
        let onClearEmptySentinel: () -> Void
        @EnvironmentObject private var lm: LocalizationManager

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(lm["onboarding.step.google.title"])
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.ink)
                    Spacer()
                    switch google.state {
                    case .signedOut:
                        Button(lm["onboarding.step.google.connect"]) {
                            onClearEmptySentinel()
                            Task { await google.signIn() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .clickCursor()
                    case .signingIn:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(lm["onboarding.step.google.connecting"])
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.ink2)
                        }
                    case .signedIn:
                        Button {
                            Task { await google.signOut() }
                        } label: {
                            Text(lm["onboarding.step.google.disconnect"])
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.ink3)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .clickCursor()
                    case .error:
                        Button(lm["onboarding.step.google.tryAgain"]) {
                            onClearEmptySentinel()
                            Task { await google.signIn() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .clickCursor()
                    }
                }

                if case .signedIn(let displayName) = google.state {
                    StatusBadge(
                        text: displayName.map { lm.t("onboarding.step.google.connectedAs", $0) } ?? lm["onboarding.step.google.connected"],
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                } else if case .error(let message) = google.state {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct MicrosoftOnboardingRow: View {
        @ObservedObject var graph: GraphSource
        let onClearEmptySentinel: () -> Void
        @EnvironmentObject private var lm: LocalizationManager

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(lm["onboarding.step.microsoft.rowTitle"])
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.ink)
                    Spacer()
                    switch graph.state {
                    case .signedOut:
                        Button(lm["settings.microsoft.connect"]) {
                            onClearEmptySentinel()
                            Task { await graph.signIn() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .clickCursor()
                    case .signingIn:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(lm["onboarding.step.microsoft.connecting"])
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.ink2)
                        }
                    case .signedIn:
                        Button {
                            Task { await graph.signOut() }
                        } label: {
                            Text(lm["onboarding.step.microsoft.disconnect"])
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.ink3)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .clickCursor()
                    case .error:
                        Button(lm["onboarding.step.microsoft.tryAgain"]) {
                            onClearEmptySentinel()
                            Task { await graph.signIn() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .clickCursor()
                    }
                }

                if case .signedIn(let displayName) = graph.state {
                    StatusBadge(
                        text: displayName.map { lm.t("onboarding.step.microsoft.connectedAs", $0) } ?? lm["onboarding.step.microsoft.connected"],
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                } else if case .error(let message) = graph.state {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Step 5: Calendars

    private var calendarsStep: some View {
        StepCard(number: stepNumber(.calendars), title: lm["onboarding.step.calendars.title"]) {
            Text(lm["onboarding.step.calendars.body"])
                .stepBody()

            VStack(alignment: .leading, spacing: 10) {
                if settings.appleCalendarEnabled && !aggregator.availableEventKitCalendars.isEmpty {
                    if aggregator.google.isConfigured || aggregator.graph.isConfigured {
                        SourceLabel(text: lm["onboarding.step.calendars.onThisMac"])
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(aggregator.availableEventKitCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: bindingForEventKitCalendar(id: calendar.calendarIdentifier)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(cgColor: calendar.cgColor))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Tokens.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(calendar.source.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Tokens.ink3)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                GoogleCalendarsList(google: aggregator.google,
                                    binding: bindingForGoogleCalendar(id:))

                GraphCalendarsList(graph: aggregator.graph,
                                   binding: bindingForGraphCalendar(id:))
            }
        }
    }

    private struct GoogleCalendarsList: View {
        @ObservedObject var google: GoogleSource
        let binding: (String) -> Binding<Bool>

        var body: some View {
            if !google.availableCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SourceLabel(text: "Google Calendar")
                    ForEach(google.availableCalendars) { calendar in
                        Toggle(isOn: binding(calendar.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(googleColor(calendar.backgroundColor))
                                    .frame(width: 8, height: 8)
                                Text(calendar.summaryOverride ?? calendar.summary ?? calendar.id)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tokens.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text("Google")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Tokens.ink3)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }

        private func googleColor(_ hex: String?) -> Color {
            guard var hex = hex else {
                return Color(.sRGB, red: 66/255, green: 133/255, blue: 244/255, opacity: 1)
            }
            if hex.hasPrefix("#") { hex.removeFirst() }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
                return Color(.sRGB, red: 66/255, green: 133/255, blue: 244/255, opacity: 1)
            }
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }

    /// Sub-view so `@ObservedObject` on the GraphSource picks up
    /// `availableCalendars` updates after sign-in.
    private struct GraphCalendarsList: View {
        @ObservedObject var graph: GraphSource
        let binding: (String) -> Binding<Bool>

        var body: some View {
            if !graph.availableCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SourceLabel(text: "Microsoft 365")
                    ForEach(graph.availableCalendars) { calendar in
                        Toggle(isOn: binding(calendar.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(.sRGB,
                                                red: 232/255,
                                                green: 115/255,
                                                blue: 42/255,
                                                opacity: 1))
                                    .frame(width: 8, height: 8)
                                Text(calendar.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tokens.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text("Outlook")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Tokens.ink3)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private struct SourceLabel: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Tokens.ink3)
        }
    }

    // MARK: - Step 7: Heads-up

    private var leadTimeStep: some View {
        StepCard(number: stepNumber(.leadTime), title: lm["onboarding.step.leadTime.title"]) {
            Text(lm["onboarding.step.leadTime.body"])
                .stepBody()

            Picker("", selection: $settings.leadTimeMinutes) {
                Text(lm["general.off"]).tag(0)
                Text("1m").tag(1)
                Text("5m").tag(5)
                Text("10m").tag(10)
                Text("15m").tag(15)
                Text("30m").tag(30)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Step 8: Launch automatically

    private var launchAtLoginStep: some View {
        StepCard(number: stepNumber(.launchAtLogin), title: lm["onboarding.step.launchAtLogin.title"]) {
            Toggle(isOn: $launchAtLogin) {
                Text(lm["onboarding.step.launchAtLogin.toggle"])
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.ink)
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { _, newValue in
                LaunchAtLoginManager.setEnabled(newValue)
            }
        }
    }

    // MARK: - Footer CTA

    private var footerCTA: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Tokens.line).frame(height: 1)
            HStack {
                Text(footerHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.ink3)
                Spacer()
                Button(action: completeOnboarding) {
                    Text(lm["onboarding.footer.getStarted"])
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .ctaFill(settings.theme.accents, cornerRadius: 10, enabled: canFinishOnboarding)
                }
                .buttonStyle(SpringPressStyle())
                .disabled(!canFinishOnboarding)
                .clickCursor()
            }
            .padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24))
            .background(Tokens.paper2)
        }
    }

    private var footerHint: String {
        if aggregator.hasAnyActiveSource { return lm["onboarding.footer.changeInPrefs"] }
        switch aggregator.permissionState {
        case .notDetermined, .granted:
            return lm.t("onboarding.footer.sourcesStepRequired", stepNumber(.calendarSources))
        case .denied, .restricted:
            return lm["onboarding.footer.accessDenied"]
        }
    }

    private var canFinishOnboarding: Bool {
        aggregator.hasAnyActiveSource
    }

    // MARK: - Actions / helpers

    private func completeOnboarding() {
        settings.onboardingCompleted = true
        dismissWindow(id: WindowID.onboarding)
    }

    private func bindingForEventKitCalendar(id: String) -> Binding<Bool> {
        calendarBinding(
            id: id,
            keyPath: \.enabledEventKitCalendarIDs,
            allIDs: { aggregator.availableEventKitCalendars.map(\.calendarIdentifier) },
            apply: aggregator.setEnabledEventKitCalendars
        )
    }

    private func bindingForGraphCalendar(id: String) -> Binding<Bool> {
        calendarBinding(
            id: id,
            keyPath: \.enabledGraphCalendarIDs,
            allIDs: { aggregator.graph.availableCalendars.map(\.id) },
            apply: aggregator.setEnabledGraphCalendars
        )
    }

    private func bindingForGoogleCalendar(id: String) -> Binding<Bool> {
        calendarBinding(
            id: id,
            keyPath: \.enabledGoogleCalendarIDs,
            allIDs: { aggregator.google.availableCalendars.map(\.id) },
            apply: aggregator.setEnabledGoogleCalendars
        )
    }

    private func calendarBinding(
        id: String,
        keyPath: ReferenceWritableKeyPath<AppSettings, Set<String>>,
        allIDs: @escaping () -> [String],
        apply: @escaping (Set<String>) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                let current = settings[keyPath: keyPath]
                return current.isEmpty || current.contains(id)
            },
            set: { newValue in
                var updated = settings[keyPath: keyPath]
                if updated.isEmpty {
                    updated = Set(allIDs())
                }
                if newValue {
                    updated.remove("__none__")
                    updated.insert(id)
                } else {
                    updated.remove(id)
                    if updated.isEmpty {
                        updated = ["__none__"]
                    }
                }
                settings[keyPath: keyPath] = updated
                apply(updated)
            }
        )
    }
}

// MARK: - Step card

/// A neutral container that hosts one onboarding step. Numbered badge on
/// the left, title and content on the right. The popup's glass surface
/// (paper fill, top-lit hairline edge).
private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NumberBadge(number: number)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .glassSurface(cornerRadius: 14)
    }
}

private struct NumberBadge: View {
    let number: Int
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        // Styled like the popup hero's status pill: tinted fill, accent
        // hairline, pill ink.
        Text("\(number)")
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(settings.theme.accents.pillInk)
            .frame(width: 26, height: 26)
            .background(Circle().fill(settings.theme.accents.pillBg))
            .overlay(Circle().strokeBorder(settings.theme.accents.pulseDot.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Reusable bits

/// The primary button used inside step cards (Grant / Connect / Try again).
/// Same gradient CTA as the popup's Join button and the full-screen alert.
private struct PrimaryStepButton: View {
    let title: String
    let action: () -> Void
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .ctaFill(settings.theme.accents, cornerRadius: 9)
        }
        .buttonStyle(SpringPressStyle())
        .clickCursor()
    }
}

/// "✓ Calendar access granted" / "✓ Connected as user@org.com" — used to
/// communicate a step has been completed.
private struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Text helpers

private extension Text {
    /// Body copy treatment shared across step cards.
    func stepBody() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(Tokens.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
