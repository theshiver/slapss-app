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
//  Visual direction follows the menu-bar popup: pastel sticker hero on a
//  monochrome canvas, consistent typography and spacing tokens, brand mark
//  rendered from the bundled AppIcon.
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
        case language, theme, calendarAccess, reminders, microsoft, calendars,
             leadTime, launchAtLogin
    }

    private var visibleSteps: [StepID] {
        var steps: [StepID] = [.language, .theme, .calendarAccess, .reminders]
        if aggregator.graph.isConfigured { steps.append(.microsoft) }
        if aggregator.permissionState == .granted { steps.append(.calendars) }
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

                        // 3 — required system permission. Always shown.
                        calendarPermissionStep

                        // 4 — independent of step 3, can be granted in any
                        // order. Optional, skippable.
                        reminderPermissionStep

                        // 5 — Exchange / Microsoft 365 OAuth. Only shown if
                        // the app has an Azure client ID configured. Optional.
                        if aggregator.graph.isConfigured {
                            MicrosoftStep(graph: aggregator.graph,
                                          number: stepNumber(.microsoft))
                        }

                        // 6–8 — preferences. Calendar picker is the only one
                        // that requires permission to be useful, so it's
                        // gated; the other two are pure preference toggles
                        // and stay visible regardless.
                        if aggregator.permissionState == .granted {
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

    /// The signature welcome sticker — same visual family as the menu-bar
    /// hero card, but oriented for a wide window: brand mark on the left,
    /// title and tagline on the right.
    private struct HeroStickerView: View {
        @Environment(\.colorScheme) private var scheme
        @EnvironmentObject private var lm: LocalizationManager
        @EnvironmentObject private var settings: AppSettings

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
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            .padding(.horizontal, 24)
        }

        @ViewBuilder
        private var cardBackground: some View {
            ZStack {
                if scheme == .dark {
                    LinearGradient(
                        colors: [accents.heroBgDarkTop, accents.heroBgDarkBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    accents.heroBgLight
                }
                // A pair of decorative blobs — fewer than the hero card so
                // the welcome reads calmer than the live meeting card.
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: accents.blob1, location: 0),
                                .init(color: accents.blob1.opacity(0), location: 0.7)
                            ]),
                            center: .center, startRadius: 0, endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .offset(x: -50, y: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: accents.blob2, location: 0),
                                .init(color: accents.blob2.opacity(0), location: 0.7)
                            ]),
                            center: .center, startRadius: 0, endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .offset(x: 40, y: -40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .allowsHitTesting(false)
        }

        private var borderColor: Color {
            scheme == .dark ? Tokens.heroBorderDark : Tokens.heroBorderLight
        }
        private var borderWidth: CGFloat { scheme == .dark ? 1 : 3 }
        private var shadowColor: Color {
            scheme == .dark
                ? Color.black.opacity(0.6)
                : Color(red: 58/255, green: 42/255, blue: 26/255, opacity: 0.18)
        }
        private var shadowRadius: CGFloat { scheme == .dark ? 14 : 10 }
        private var shadowY: CGFloat { scheme == .dark ? 10 : 8 }
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

    // MARK: - Step 3: Calendar permission

    private var calendarPermissionStep: some View {
        StepCard(number: stepNumber(.calendarAccess), title: lm["onboarding.step.calendarAccess.title"]) {
            switch aggregator.permissionState {
            case .notDetermined:
                Text(lm["onboarding.step.calendarAccess.body"])
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
                StatusBadge(text: lm["onboarding.step.calendarAccess.granted"], systemImage: "checkmark.circle.fill", tint: .green)
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

    // MARK: - Step 5: Microsoft 365 / Exchange

    /// Lives in its own struct so it can `@ObservedObject` the GraphSource
    /// directly. Without that observation, sign-in state changes (which
    /// publish from inside `aggregator.graph`) wouldn't trigger a re-render
    /// of this step.
    private struct MicrosoftStep: View {
        @ObservedObject var graph: GraphSource
        /// Computed by the parent from the visible-step sequence.
        let number: Int
        @EnvironmentObject private var lm: LocalizationManager

        var body: some View {
            StepCard(number: number, title: lm["onboarding.step.microsoft.title"]) {
                switch graph.state {
                case .signedOut:
                    Text(lm["onboarding.step.microsoft.body"])
                        .stepBody()
                    PrimaryStepButton(title: lm["settings.microsoft.connect"]) {
                        Task { await graph.signIn() }
                    }
                case .signingIn:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(lm["onboarding.step.microsoft.connecting"])
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.ink2)
                    }
                case .signedIn(let displayName):
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBadge(
                            text: displayName.map { lm.t("onboarding.step.microsoft.connectedAs", $0) } ?? lm["onboarding.step.microsoft.connected"],
                            systemImage: "checkmark.circle.fill",
                            tint: .green
                        )
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
                    }
                case .error(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryStepButton(title: lm["onboarding.step.microsoft.tryAgain"]) {
                            Task { await graph.signIn() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 6: Calendars

    private var calendarsStep: some View {
        StepCard(number: stepNumber(.calendars), title: lm["onboarding.step.calendars.title"]) {
            Text(lm["onboarding.step.calendars.body"])
                .stepBody()

            VStack(alignment: .leading, spacing: 10) {
                if !aggregator.availableEventKitCalendars.isEmpty {
                    if aggregator.graph.isConfigured {
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

                // Graph calendars only render after sign-in. Anchor the list
                // on aggregator.graph so SwiftUI re-evaluates this branch
                // when the user signs in/out during onboarding.
                GraphCalendarsList(graph: aggregator.graph,
                                   binding: bindingForGraphCalendar(id:))
            }
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
                        .foregroundStyle(Tokens.joinFg)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(canFinishOnboarding ? settings.theme.accents.joinBg : Tokens.ink4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canFinishOnboarding)
                .clickCursor()
            }
            .padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24))
            .background(Tokens.paper2)
        }
    }

    private var footerHint: String {
        // Exchange/Microsoft 365 users who signed in via Graph don't need
        // local Calendar.app access at all — don't block them on a
        // permission they may never grant.
        if isGraphSignedIn { return lm["onboarding.footer.changeInPrefs"] }
        switch aggregator.permissionState {
        case .notDetermined:  return lm["onboarding.footer.step1Required"]
        case .denied, .restricted: return lm["onboarding.footer.accessDenied"]
        case .granted:        return lm["onboarding.footer.changeInPrefs"]
        }
    }

    /// Get Started is enabled once the user has SOME way to see meetings:
    /// local Calendar.app access, or a signed-in Microsoft 365/Exchange
    /// account. Blocking purely on EventKit permission stranded
    /// Exchange-only users who never touch Calendar.app.
    private var canFinishOnboarding: Bool {
        aggregator.permissionState == .granted || isGraphSignedIn
    }

    private var isGraphSignedIn: Bool {
        if case .signedIn = aggregator.graph.state { return true }
        return false
    }

    // MARK: - Actions / helpers

    private func completeOnboarding() {
        settings.onboardingCompleted = true
        dismissWindow(id: WindowID.onboarding)
    }

    private func bindingForEventKitCalendar(id: String) -> Binding<Bool> {
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

    private func bindingForGraphCalendar(id: String) -> Binding<Bool> {
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

// MARK: - Step card

/// A neutral container that hosts one onboarding step. Numbered badge on
/// the left, title and content on the right. Background is `--paper-2` with
/// a hairline `--line` border, matching the popover's section conventions.
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
        .background(Tokens.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Tokens.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NumberBadge: View {
    let number: Int
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            // Was a hardcoded warm brown (0xA35A18) — that's exactly the
            // sunset pillInk, so the themed token keeps v1 rendering intact.
            .foregroundStyle(settings.theme.accents.pillInk)
            .frame(width: 26, height: 26)
            .background(
                LinearGradient(
                    colors: [settings.theme.accents.brandGradTop,
                             settings.theme.accents.brandGradBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Reusable bits

/// The chunky dark-on-light primary button used inside step cards (Grant /
/// Connect / Try again). Uses the same `joinBg`/`joinFg` palette as the
/// popover hero's Join button so the visual vocabulary stays consistent.
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
                .foregroundStyle(Tokens.joinFg)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.theme.accents.joinBg)
                )
        }
        .buttonStyle(.plain)
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
