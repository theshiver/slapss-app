//
//  ContentView.swift
//  slapss
//
//  Menu bar popover content. Shows the next upcoming meeting and quick controls.
//
//  Visual direction: Variation H — "Soft sticker" (per design handoff
//  `design_handoff_slapss_menu_bar`). The hero is a tilted pastel sticker
//  card; everything else stays disciplined and quiet. Light + dark modes
//  follow the system. Brand logo uses the bundled AppIcon.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Design tokens
//
// CSS custom-property names from the handoff are mirrored here so the spec
// can be cross-referenced. Each token is a dynamic Color that resolves to the
// right shade for the active appearance.

private extension Color {
    /// Build a Color from a 24-bit hex literal: `Color.hex(0x1F1D2B)`.
    static func hex(_ hex: UInt32, opacity: Double = 1.0) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: opacity)
    }

    /// Picks `light` or `dark` based on the active NSAppearance. We reach
    /// down to NSColor with a dynamic provider so the resolution is automatic
    /// across appearance changes without a SwiftUI view re-render.
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}

/// Module-internal so other views (Onboarding, future panels) can pull
/// from the same palette without redefining the dynamic light/dark colors.
enum Tokens {
    // Surfaces
    static let paper   = Color(light: .hex(0xFFFFFF), dark: .hex(0x1A1820))
    static let paper2  = Color(light: .hex(0xF7F6FB), dark: .hex(0x221F2A))
    static let paper3  = Color(light: .hex(0xEFEEF7), dark: .hex(0x2A2734))

    // Ink (text)
    static let ink     = Color(light: .hex(0x1F1D2B), dark: .hex(0xF3F0FB))
    static let ink2    = Color(light: .hex(0x4A4860), dark: .hex(0xBFBACF))
    static let ink3    = Color(light: .hex(0x8B8AA0), dark: .hex(0x7C7791))
    static let ink4    = Color(light: .hex(0xB9B8C9), dark: .hex(0x4D4960))

    // Lines / hairlines
    static let line    = Color(light: .hex(0x1F1D2B, opacity: 0.06),
                               dark:  .hex(0xFFFFFF, opacity: 0.06))
    static let line2   = Color(light: .hex(0x1F1D2B, opacity: 0.10),
                               dark:  .hex(0xFFFFFF, opacity: 0.10))

    // Sticker hero — neutral border (theme-independent)
    static let heroBorderLight   = Color.white
    static let heroBorderDark    = Color.hex(0xFFFFFF, opacity: 0.08)

    // Join button foreground (neutral — the fill is themed, see
    // AppTheme.Accents.joinBg)
    static let joinFg  = Color(light: .hex(0xFFFFFF), dark: .hex(0x1A1820))

    // NOTE (theming): the accent layer that used to live here —
    // pillBg/pillInk/pulseDot, heroTitle/Time/Meta, heroBg*, blobPeach/Rose/
    // Sky (now blob1/2/3), brandGrad*, joinBg — moved to `AppTheme.Accents`
    // (Theme.swift). Views read them via `settings.theme.accents.<name>` so
    // theme switches re-render through the ObservableObject path.
}

// MARK: - MenuBarContentView (entry point used by `MenuBarExtra`)

struct MenuBarContentView: View {
    @EnvironmentObject private var aggregator: CalendarAggregator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var scheduler: AlertScheduler
    @EnvironmentObject private var lm: LocalizationManager

    /// Tick the popup once a minute so the "Up next · 12m" pill, the live
    /// in-progress remainder, and the buckets between Later/Earlier all
    /// follow real time without manual nudging.
    @StateObject private var clock = TickClock(interval: 30)

    /// macOS 14+ environment action for opening the Settings scene declared
    /// on the App. We use this instead of `SettingsLink` because the link
    /// view is unreliable inside `MenuBarExtra(.window)` — especially when
    /// wrapped in custom button styling, clicks were intermittently swallowed.
    @Environment(\.openSettings) private var openSettings

    /// Used to re-surface the onboarding window from the popover stub if
    /// the user closed it before completing setup.
    @Environment(\.openWindow) private var openWindow

    /// Which agenda rows are expanded. Lifted out of `AgendaRow` (was a local
    /// `@State`) so `NoUpNextLine` can expand the matching row from outside.
    /// A Set — multiple rows can stay expanded at once, as before.
    @State private var expandedEventIDs: Set<String> = []

    /// Measured height of the scrollable agenda area. The popover previously
    /// sized intrinsically with no cap — a day with 12+ meetings grew taller
    /// than a laptop screen. The agenda now lives in a ScrollView whose
    /// height tracks the content up to `agendaMaxHeight`, so short days look
    /// exactly as before and long days scroll.
    @State private var agendaContentHeight: CGFloat = 0

    /// Height cap for the scrollable agenda area (header and footer stay
    /// pinned outside it). ~560pt keeps the whole popover comfortably inside
    /// a MacBook Air screen minus menu bar.
    private static let agendaMaxHeight: CGFloat = 560

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                regularView
            } else {
                onboardingStub
            }
        }
        .background(Tokens.paper)
        .onAppear {
            Self.disableMenuBarPopoverAnimation()
            // Wire the right-click "Preferences" menu item to SwiftUI's
            // openSettings action. Must be set here (inside the SwiftUI
            // environment) because openSettings is an environment value that
            // isn't accessible from plain AppKit code.
            // Same path as the footer button — includes the explicit
            // bring-to-front (the window otherwise opens behind other apps).
            StatusMenuController.shared.onOpenPreferences = {
                openPreferences()
            }
            // Lets the right-click context menu render its strings in the
            // user's chosen language instead of hardcoded English.
            StatusMenuController.shared.lm = lm
        }
        .task {
            await aggregator.start(
                enabledEventKitCalendars: settings.enabledEventKitCalendarIDs,
                enabledGraphCalendars: settings.enabledGraphCalendarIDs
            )
            // Wire scheduler to aggregator + settings on first appearance.
            // attach() is idempotent so subsequent calls are no-ops.
            scheduler.attach(aggregator: aggregator, settings: settings, lm: lm)
            // First-run reminder permission prompt. Only fires once per app
            // lifetime (the OS only returns .notDetermined until the user
            // answers the dialog). Gated by `onboardingCompleted` so we don't
            // pile a second permission prompt on top of the calendar one
            // during the welcome flow.
            if settings.onboardingCompleted
                && settings.showReminders
                && aggregator.reminderPermissionState == .notDetermined {
                await aggregator.requestReminderAccess()
            }
        }
    }

    // MARK: Onboarding stub
    //
    // While `onboardingCompleted` is false, the menu-bar popover renders this
    // tiny placeholder instead of the full first-run flow. Onboarding itself
    // lives in a separate Window scene (see `slapssApp.swift`), and we open
    // it automatically on app launch from `MenuBarLabel.task`. The stub is a
    // safety net for users who close the window mid-setup — clicking the
    // status item gets them back into onboarding instead of a confusing
    // empty popover.

    private var onboardingStub: some View {
        VStack(spacing: 0) {
            HeaderView(now: Date())

            VStack(alignment: .leading, spacing: 12) {
                Text(lm["popover.stub.title"])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                Text(lm["popover.stub.body"])
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                    Self.dismissMenuBarPopover()
                } label: {
                    Text(lm["popover.stub.openSetup"])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.joinFg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(settings.theme.accents.joinBg)
                        )
                }
                .buttonStyle(.plain)
                .clickCursor()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            FooterView(
                onPreferences: openPreferences,
                onQuit: { NSApp.terminate(nil) }
            )
        }
        .frame(width: 360)
        .transaction { txn in txn.disablesAnimations = true }
    }

    // MARK: Regular content

    private var regularView: some View {
        // `transaction { … disablesAnimations = true }` neutralizes any
        // implicit animation that an outer scope (or a sibling `.onAppear`
        // running `withAnimation`) might try to attach to the popup's
        // layout. Without this, the agenda's first data load can ride a
        // residual animation curve and visibly resize the whole popup.
        // The pulse dot still animates because it uses an explicit
        // `.animation(_:value:)` modifier, which is independent of
        // transactions.
        VStack(spacing: 0) {
            HeaderView(now: clock.date)

            // Scrollable middle: permission states are short, but the agenda
            // can outgrow the screen on busy days. The ScrollView's height
            // tracks the measured content height up to `agendaMaxHeight`, so
            // it behaves exactly like the old intrinsic layout until the cap
            // is hit — then it scrolls, with header/footer pinned.
            ScrollView {
                Group {
                    switch aggregator.permissionState {
                    case .notDetermined:
                        PermissionPromptView { Task { await aggregator.requestAccess() } }
                    case .denied, .restricted:
                        PermissionDeniedView()
                    case .granted:
                        agendaSections
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    agendaContentHeight = newHeight
                }
            }
            .frame(height: min(agendaContentHeight, Self.agendaMaxHeight))

            FooterView(
                onPreferences: openPreferences,
                onQuit: { NSApp.terminate(nil) },
                presentingModeEnabled: scheduler.presentingModeEnabled,
                onTogglePresenting: { scheduler.togglePresentingMode() }
            )
        }
        .frame(width: 360)
        .transaction { txn in txn.disablesAnimations = true }
    }

    // MARK: Agenda

    private var agendaSections: some View {
        let now = clock.date
        // The aggregator caches a 24-hour rolling window so the scheduler can
        // see early-morning events the night before. The popover should only
        // show TODAY — that's what "Later today" / "Earlier today" implies.
        let visibleUpcoming = settings.showReminders
            ? aggregator.upcomingMeetings
            : aggregator.upcomingMeetings.filter { !$0.isReminder }
        let visiblePastToday = settings.showReminders
            ? aggregator.pastMeetingsToday
            : aggregator.pastMeetingsToday.filter { !$0.isReminder }
        let upcomingToday = visibleUpcoming.filter {
            Calendar.current.isDateInToday($0.startDate)
        }

        let upcoming = upcomingToday.filter { $0.startDate > now }
        let past = settings.showPastMeetingsToday ? visiblePastToday : []

        // Hero promotion defers to the scheduler's shared selector so the card
        // and the menu-bar label always agree on which meeting is "current."
        // The card is meeting-only and ignores menu-bar mutes — hence
        // includeReminders: false / respectMutes: false.
        let heroEvent = scheduler.priorityMeeting(
            now: now,
            includeReminders: false,
            respectMutes: false
        )

        // Strip the hero event from the "Later today" list so it doesn't
        // appear twice — but everything else (including reminders that fall
        // in the same window) stays.
        let later: [MeetingEvent]
        if let hero = heroEvent {
            later = upcoming.filter { $0.id != hero.id }
        } else {
            later = upcoming
        }

        return VStack(spacing: 0) {
            if let hero = heroEvent {
                HeroCardView(
                    event: hero,
                    now: now,
                    authUser: settings.authUser(forCalendarID: hero.calendarID)
                )
            } else if let nextAny = upcoming.first {
                // Tapping expands the matching agenda row below — the line
                // references a concrete meeting, so it should lead there.
                NoUpNextLine(next: nextAny, expanded: expandedBinding(for: nextAny.id))
            }

            // Hide-bar pill — only renders when there's currently a meeting
            // populating the menu-bar text and the user can therefore
            // meaningfully hide it. (We never offer to hide reminders here:
            // the menu bar text only ever pins meetings.) Sits BELOW the hero:
            // it's a secondary, rarely-used action and shouldn't occupy the
            // popover's most prominent slot above the card.
            if let muteable = scheduler.currentMenuBarMeeting(now: now) {
                HideReminderBar(meeting: muteable) {
                    scheduler.muteFromMenuBar(muteable.id)
                }
            }

            if !later.isEmpty {
                SectionLabel(title: lm["popover.later"], count: later.count)
                LazyVStack(spacing: 0) {
                    ForEach(later) { ev in
                        AgendaRow(
                            event: ev,
                            dimmed: false,
                            onComplete: ev.isReminder ? { scheduler.completeReminder(ev) } : nil,
                            expanded: expandedBinding(for: ev.id)
                        )
                    }
                }
            }

            if !past.isEmpty {
                SectionLabel(title: lm["popover.earlier"], count: past.count)
                LazyVStack(spacing: 0) {
                    ForEach(past) { ev in
                        AgendaRow(
                            event: ev,
                            dimmed: true,
                            onComplete: ev.isReminder ? { scheduler.completeReminder(ev) } : nil,
                            expanded: expandedBinding(for: ev.id)
                        )
                    }
                }
            }

            // Empty-state catch-all: no hero, no later, no past. A bare text
            // line felt flat next to the sticker hero's personality — a
            // quiet icon + two-line copy matches the rest of the popover's
            // warmth without competing with the (absent) hero card.
            if heroEvent == nil && later.isEmpty && past.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Tokens.ink4)
                    Text(lm["popover.noMeetings"])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.ink2)
                    Text(lm["popover.noMeetings.subtitle"])
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 26)
            }

            Spacer(minLength: 6)
        }
    }

    /// Two-way binding into `expandedEventIDs` for a single event ID.
    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedEventIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedEventIDs.insert(id)
                } else {
                    expandedEventIDs.remove(id)
                }
            }
        )
    }

    // MARK: Settings deep-link

    /// Open the Settings window and dismiss the menu bar popover.
    ///
    /// Why we don't just use `SettingsLink`:
    ///  - In `MenuBarExtra(.window)`, the link is flaky — especially once
    ///    its label has custom padding / hoverBackground / contentShape, the
    ///    underlying tap gesture sometimes refuses to fire.
    ///  - There's also no public API to close the popover after the link
    ///    triggers, so the popover stays floating in front of Settings.
    ///
    /// Calling `openSettings()` from the environment is reliable; for
    /// dismissing the popover we walk `NSApp.windows` using `menuBarExtraWindows()`.
    private func openPreferences() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        // Defer to the next runloop tick so the Settings window has a chance
        // to register itself before we close the popover that opened it —
        // and before we can order it to the front.
        DispatchQueue.main.async {
            Self.dismissMenuBarPopover()
            Self.bringSettingsWindowToFront()
        }
    }

    /// The Settings scene's window can spawn BEHIND other apps' windows:
    /// since macOS 14, `NSApp.activate(ignoringOtherApps:)` is cooperative —
    /// the system may defer or ignore it — and for an accessory (menu-bar)
    /// app nothing else forces a newly created window to the front. Locate
    /// the window and order it front explicitly. Runs on the tick after
    /// `openSettings()`, when the window has registered in `NSApp.windows`.
    private static func bringSettingsWindowToFront() {
        // SwiftUI's Settings scene window carries the identifier
        // "com_apple_SwiftUI_Settings" (observed value, not documented API —
        // hence the `contains` match plus a structural fallback). The
        // fallback picks any visible titled window that isn't the onboarding
        // scene; the popover is excluded by its lack of `.titled`.
        let settingsWindow = NSApp.windows.first {
            $0.identifier?.rawValue.contains("Settings") == true
        } ?? NSApp.windows.first {
            $0.styleMask.contains(.titled)
                && $0.isVisible
                && $0.identifier?.rawValue != WindowID.onboarding
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private static func dismissMenuBarPopover() {
        menuBarExtraWindows().forEach { $0.close() }
    }

    /// Tell the menu-bar popover window to skip AppKit's default fade/scale
    /// appearance animation, so clicking the status item snaps the popup
    /// open instantly. Setting `animationBehavior` is idempotent, so it's
    /// safe to call this on every `.onAppear`. The first open of a session
    /// may still play the system animation (the window doesn't exist before
    /// the user clicks); every subsequent open is instant.
    private static func disableMenuBarPopoverAnimation() {
        menuBarExtraWindows().forEach { $0.animationBehavior = .none }
    }

    /// Locates the MenuBarExtra popover window(s) using only public API.
    ///
    /// SwiftUI's `MenuBarExtra` with `.window` style creates a borderless,
    /// untitled window that sits directly below the menu bar. We identify it
    /// by three observable properties that are exclusive to it in practice:
    ///   1. No `.titled` style-mask bit (it has no title bar).
    ///   2. Its window level is above `.normal` (it floats over app content).
    ///   3. Its top edge (maxY) is at or just below the bottom of the menu bar.
    ///
    /// This avoids inspecting any private class names while still being
    /// precise enough that other floating panels (e.g. color picker) are
    /// excluded by the positional constraint.
    private static func menuBarExtraWindows() -> [NSWindow] {
        guard let screen = NSScreen.main else { return [] }
        // Bottom edge of the system menu bar in screen coordinates.
        let menuBarBottom = screen.frame.maxY - NSStatusBar.system.thickness
        return NSApp.windows.filter { window in
            !window.styleMask.contains(.titled) &&
            window.level.rawValue > NSWindow.Level.normal.rawValue &&
            // Allow a small tolerance for system chrome / drop shadows.
            window.frame.maxY <= menuBarBottom + 4 &&
            window.frame.maxY >= menuBarBottom - 60
        }
    }
}

// MARK: - Header

/// Brand row — `[AppIcon] Slapss / Today, EEE MMM d`.
///
/// Per the user's request, the brand glyph is the bundled application icon
/// (rendered through `NSApp.applicationIconImage`) clipped into an 8pt
/// rounded square. This is the same artwork the Dock and About box show, so
/// the popup feels native.
private struct HeaderView: View {
    let now: Date
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandLogoView()

            VStack(alignment: .leading, spacing: 1) {
                Text("Slapss")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Tokens.ink)
                Text(Self.dateLabel(for: now, lm: lm))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Tokens.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }

    /// Spec format: "Today, Thu May 7". Locked to `lm.language` (not the
    /// system locale) so weekday/month names follow the in-app language
    /// switcher — otherwise switching to Turkish still showed English weekday
    /// names on a system set to English. Uses a localized template (not a
    /// literal `"EEE MMM d"` pattern) so element ORDER also follows the
    /// locale — Turkish renders "13 Tem Pzt", not the English "Pzt Tem 13".
    private static func dateLabel(for date: Date, lm: LocalizationManager) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lm.language.rawValue)
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return String(format: lm["general.today"], f.string(from: date))
    }
}

/// 28×28 rounded-square brand mark backed by the bundled app icon. The icon
/// fills the square edge-to-edge — no tinted backdrop behind it — so the
/// header shows the artwork itself rather than the icon floating on a colored
/// tile.
private struct BrandLogoView: View {
    var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback if the icon resource isn't loadable for some
                // reason — keeps the row from collapsing visually.
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.hex(0xA35A18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The app's bundled icon, loaded from the asset catalog. We use the
    /// running app's icon (not a named asset) so renaming the icon in
    /// Assets.xcassets doesn't silently break this view.
    private static var appIcon: NSImage? {
        // NSApp.applicationIconImage is non-optional in practice but documented
        // as nullable in older SDKs — keep the optional dance for safety.
        let icon = NSApplication.shared.applicationIconImage
        return icon
    }
}

// MARK: - Hide reminder bar

private struct HideReminderBar: View {
    let meeting: MeetingEvent
    let onHide: () -> Void
    @State private var hovering = false
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        Button(action: onHide) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.ink3)
                Text(lm.t("popover.hideFromMenuBar", meeting.title))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Tokens.paper2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Tokens.line, lineWidth: 1)
                    )
            )
            .opacity(hovering ? 0.85 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onHover { hovering = $0 }
        .clickCursor()
    }
}

// MARK: - Permission states (slot in where the agenda would go)

private struct PermissionPromptView: View {
    let onGrant: () -> Void
    @EnvironmentObject private var lm: LocalizationManager
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lm["popover.permissionPrompt"])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.ink)
            Button(lm["general.continue"], action: onGrant)
                .buttonStyle(.borderedProminent)
                .clickCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionDeniedView: View {
    @EnvironmentObject private var lm: LocalizationManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lm["popover.permissionDenied"])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
            Text(lm["popover.permissionDeniedHelp"])
                .font(.system(size: 11))
                .foregroundStyle(Tokens.ink3)
            Button(lm["general.openSystemSettings"]) {
                SystemSettingsOpener.openCalendarPrivacy()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clickCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Deep-links into System Settings' privacy panes. Centralized so both the
/// popover's denied state and onboarding's denied step use the same URL.
enum SystemSettingsOpener {
    static func openCalendarPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openRemindersPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Hero card (sticker)

/// The signature element: a slightly tilted pastel "sticker" with a die-cut
/// white border, decorative blobs, and a folded-corner detail.
///
/// All the visual character of the popup lives in this view. Everything
/// below the hero (sections, rows, footer) is intentionally monochrome.
private struct HeroCardView: View {
    let event: MeetingEvent
    let now: Date
    /// Google `authuser` index for this meeting's calendar, if configured.
    var authUser: Int? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var popoverVisibility: PopoverVisibilityMonitor
    @EnvironmentObject private var settings: AppSettings

    private var accents: AppTheme.Accents { settings.theme.accents }

    var body: some View {
        cardContent
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            // `.compositingGroup()` rasterises the card (text + shadows +
            // animated gradients) into a single offscreen layer BEFORE the
            // -0.6° rotation is applied. Without this, SwiftUI on macOS can
            // re-rasterise individual subviews (notably the text) inside the
            // already-rotated coordinate space, and the gradient siblings'
            // NSView-backed coordinate flip leaks through onto the glyphs —
            // which is what produced the mirrored "JOIN" / "15m" text in v1.
            .compositingGroup()
            .rotationEffect(.degrees(-0.6), anchor: .top)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 12, trailing: 14))
            // Drive pulse from real popover visibility — see BlobsBackground
            // for why onAppear/onDisappear cannot be used here.
            // The actual animation curve is attached to the pulse Circle via
            // `.animation(_:value:)` below; this plain assignment avoids
            // creating a global animation transaction.
            .onChange(of: popoverVisibility.isVisible) { _, isVisible in
                pulse = isVisible
            }
    }

    private var cardContent: some View {
        ZStack(alignment: .topLeading) {
            BlobsBackground()                     // z-index 0 — large soft blobs
            FloatingDotsBackground()              // z-index 1 — small drifting dots
            FoldCornerOverlay()                   // sits on top-right
            VStack(alignment: .leading, spacing: 0) {
                upNextPill
                Text(event.title)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(accents.heroTitle)
                    .padding(.top, 8)
                    .lineLimit(2)

                Text(timeLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accents.heroTime)
                    .padding(.top, 4)

                metaList.padding(.top, 12)

                if let url = event.joinURL {
                    JoinButton(url: url, scheme: scheme, authUser: authUser)
                        .padding(.top, 14)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
            // Belt-and-suspenders: even with the outer `.compositingGroup()`
            // on the rotation, isolate the text VStack into its own group so
            // its glyph rasterisation never shares a backing layer with the
            // animated blob/dot siblings underneath. This is the layer where
            // the v1 mirror bug actually manifested.
            .compositingGroup()
        }
        // Stop the ZStack from collapsing to its first child's intrinsic
        // size between layout passes. The card has a min-width (padding +
        // glyphs) but no max — anchoring with `.infinity` removes the
        // "first sibling decides our coordinate system" race that the v1
        // FloatingDotsBackground comment described.
        .frame(maxWidth: .infinity)
        // Nuclear fix for the coordinate-system flip bug. `.drawingGroup()`
        // routes the ENTIRE ZStack (blobs, dots, text, icons, join button)
        // through Metal's rendering pipeline, which is fully independent of
        // NSView's isFlipped / CALayer contentsAreFlipped / geometryFlipped
        // properties. The CA-backed blob and dot animations can no longer
        // inject a non-flipped coordinate context into the glyph rasteriser
        // because the rendering never enters the AppKit layer tree at all —
        // it goes: SwiftUI layout → Metal texture → composited CALayer image.
        // The inner `.compositingGroup()` on the text VStack is kept as
        // belt-and-suspenders isolation within the Metal pass.
        // `opaque: false` preserves the gradient blobs' transparent edges.
        .drawingGroup(opaque: false)
    }

    // MARK: pieces

    private var upNextPill: some View {
        HStack(spacing: 6) {
            ZStack {
                // Pulsing ring — hidden when Reduce Motion is enabled.
                if !reduceMotion {
                    Circle()
                        .fill(accents.pulseDot.opacity(0.45))
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 2.6 : 1.0)
                        .opacity(pulse ? 0 : 0.45)
                        // Scoped to the ring's `pulse`-driven properties only —
                        // does NOT create a global animation transaction, so the
                        // popup window and other views won't inherit the curve.
                        .animation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                            value: pulse
                        )
                }
                Circle()
                    .fill(accents.pulseDot)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 12, height: 12) // give the breathing ring room

            Text(pillText)
                .font(.system(size: 10.5, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(accents.pillInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(accents.pillBg)
        )
    }

    /// "Up next · 12m" or "Live · 18m left" depending on hero state.
    private var pillText: String {
        let untilStart = event.startDate.timeIntervalSince(now)
        if untilStart <= 0 && now < event.endDate {
            // Live, in progress.
            let left = max(1, Int((event.endDate.timeIntervalSince(now) + 30) / 60))
            return lm.t("popover.live", left)
        } else {
            let mins = max(0, Int((untilStart + 30) / 60))
            return lm.t("popover.upNext", mins)
        }
    }

    /// "14:00 – 14:30 · 30m"
    private var timeLine: String {
        return "\(event.timeRangeString) · \(event.durationString(lm: lm))"
    }

    @ViewBuilder
    private var metaList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let location = event.location, !location.isEmpty {
                MetaLine(systemImage: "mappin.circle.fill", text: location)
            }
            if !event.attendees.isEmpty {
                MetaLine(
                    systemImage: "person.2.fill",
                    text: event.attendees.joined(separator: ", ")
                )
            }
        }
    }

    // MARK: tokens dependent on scheme

    @ViewBuilder
    private var cardBackground: some View {
        if scheme == .dark {
            LinearGradient(
                colors: [accents.heroBgDarkTop, accents.heroBgDarkBottom],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            accents.heroBgLight
        }
    }
    private var borderColor: Color {
        scheme == .dark ? Tokens.heroBorderDark : Tokens.heroBorderLight
    }
    private var borderWidth: CGFloat { scheme == .dark ? 1 : 3 }
    private var shadowColor: Color {
        scheme == .dark
            ? Color.black.opacity(0.7)
            : Color.hex(0x3A2A1A, opacity: 0.18)
    }
    private var shadowRadius: CGFloat { scheme == .dark ? 11 : 7 }
    private var shadowY: CGFloat { scheme == .dark ? 8 : 6 }
}

/// One row of the hero meta block — icon + text, ellipsised on overflow.
private struct MetaLine: View {
    let systemImage: String
    let text: String
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.ink3)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(settings.theme.accents.heroMeta)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Three radial-gradient blobs absolutely placed inside the hero card.
/// Each blob drifts in a different direction and at a different speed,
/// creating a parallax depth effect. Different durations (6 / 8 / 10 s)
/// mean the blobs are never in sync — the background always feels alive.
///
/// Animation is driven by `PopoverVisibilityMonitor.isVisible` rather than
/// `onAppear/onDisappear`. `MenuBarExtra(.window)` keeps the view graph alive
/// permanently — `onDisappear` never fires on popover close, so any
/// `.repeatForever()` animation started in `onAppear` runs at 60 fps with
/// nothing on screen, consuming ~40% CPU. The monitor observes the real
/// NSWindow key/close events and is the only reliable signal.
private struct BlobsBackground: View {
    @EnvironmentObject private var popoverVisibility: PopoverVisibilityMonitor
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accents: AppTheme.Accents { settings.theme.accents }

    var body: some View {
        ZStack {
            // Blob 1 — largest, bottom-left, 120pt  (slowest — feels furthest away)
            blob(color: accents.blob1, size: 120)
                .offset(x: -40 + ((!reduceMotion && popoverVisibility.isVisible) ?  14 : 0),
                        y:  40 + ((!reduceMotion && popoverVisibility.isVisible) ? -10 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 10).repeatForever(autoreverses: true),
                           value: popoverVisibility.isVisible)

            // Blob 2 — medium, top-right, 90pt  (medium speed)
            blob(color: accents.blob2, size: 90)
                .offset(x:  30 + ((!reduceMotion && popoverVisibility.isVisible) ? -12 : 0),
                        y: -30 + ((!reduceMotion && popoverVisibility.isVisible) ?  14 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .animation(reduceMotion ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true),
                           value: popoverVisibility.isVisible)

            // Blob 3 — smallest, bottom-right, 60pt  (fastest — feels closest)
            blob(color: accents.blob3, size: 60)
                .offset(x: -60 + ((!reduceMotion && popoverVisibility.isVisible) ?  10 : 0),
                        y:  20 + ((!reduceMotion && popoverVisibility.isVisible) ? -12 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .animation(reduceMotion ? nil : .easeInOut(duration: 6).repeatForever(autoreverses: true),
                           value: popoverVisibility.isVisible)
        }
        // Mirror the FloatingDotsBackground fix: pin the outer ZStack's size
        // to the card content area rather than letting it negotiate per-child.
        // Same root cause as the documented `Color.clear` flip — when the
        // ZStack collapses around its children between layout passes, the
        // NSView coordinate system underneath leaks into the sibling text
        // VStack and rasterises glyphs mirrored. Pinning the frame removes
        // the collapse cycle.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.disablesAnimations = false }
        .allowsHitTesting(false)
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0), location: 0.7)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
    }
}

/// Small floating dots that drift lazily across the hero card background.
///
/// Each dot starts at a fixed origin (in points from the card's top-leading
/// corner) and eases toward a target offset, then reverses — creating a slow,
/// breathing movement. `Color.clear` expands the ZStack to fill the card so
/// the dot positions are consistent regardless of card height.
///
/// Animation is scoped via `.animation(_:value:)` on each dot so it never
/// cascades to sibling views (same caution applied to the pulse dot above).
/// Driven by `PopoverVisibilityMonitor` — see `BlobsBackground` for details
/// on why `onAppear/onDisappear` cannot be used here.
private struct FloatingDotsBackground: View {
    @EnvironmentObject private var popoverVisibility: PopoverVisibilityMonitor
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accents: AppTheme.Accents { settings.theme.accents }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Small accent dots (blob3 hue)
            dot(color: accents.blob3, size: 5, x:  38, y:  58, dx:  22, dy:  14, t:  1.8)
            dot(color: accents.blob3, size: 6, x: 122, y:  96, dx:  14, dy: -14, t:  2.2)
            dot(color: accents.blob3, size: 4, x: 288, y: 118, dx: -18, dy:  -8, t:  2.0)

            // Medium accent dots (blob2 hue)
            dot(color: accents.blob2, size: 4, x: 208, y:  26, dx: -16, dy:  18, t:  2.4)
            dot(color: accents.blob2, size: 5, x: 258, y:  74, dx: -18, dy:  10, t:  1.7)
            dot(color: accents.blob2, size: 6, x:  54, y: 168, dx:  18, dy: -16, t:  2.6)

            // Primary accent dots (blob1 hue)
            dot(color: accents.blob1, size: 4, x:  74, y: 134, dx:  16, dy: -18, t:  1.9)
            dot(color: accents.blob1, size: 5, x: 184, y:  46, dx: -12, dy:  22, t:  2.1)
        }
        // Fill the card content area without using Color.clear — on macOS,
        // Color.clear's NSView backing can flip the coordinate system of the
        // parent ZStack, causing all sibling views (text, icons) to mirror.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Re-enable animations suppressed by the parent VStack's transaction.
        .transaction { $0.disablesAnimations = false }
        .allowsHitTesting(false)
    }

    private func dot(
        color: Color, size: CGFloat,
        x: CGFloat, y: CGFloat,
        dx: CGFloat, dy: CGFloat,
        t: Double
    ) -> some View {
        Circle()
            .fill(color.opacity(0.55))
            .frame(width: size, height: size)
            .offset(x: x + ((!reduceMotion && popoverVisibility.isVisible) ? dx : 0),
                    y: y + ((!reduceMotion && popoverVisibility.isVisible) ? dy : 0))
            // Scoped animation — does NOT create a global transaction.
            // Suppressed when Reduce Motion is enabled.
            .animation(
                reduceMotion ? nil : .easeInOut(duration: t).repeatForever(autoreverses: true),
                value: popoverVisibility.isVisible
            )
    }
}

/// A 22×22 "folded corner" sticker detail at the top-right. The visible
/// triangle is filled with the popup's paper color so it reads as a fold
/// over the page behind. A subtle drop shadow gives it lift.
private struct FoldCornerOverlay: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        FoldShape()
            .fill(scheme == .dark ? Tokens.paper : Color.white)
            .frame(width: 22, height: 22)
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: -1, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
    }
}

private struct FoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Upper-right triangle. Diagonal goes from top-left to bottom-right
        // of the box; everything above-and-right of it is filled.
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct JoinButton: View {
    let url: URL
    let scheme: ColorScheme
    var authUser: Int? = nil
    @State private var pressed = false
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            // Press ripple, then open. The animation is short so the user
            // sees an acknowledgement even on snappy systems.
            withAnimation(.easeOut(duration: 0.08)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.08)) { pressed = false }
                MeetingURLOpener.open(url, authUser: authUser)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(lm["popover.join"])
                    .font(.system(size: 12, weight: scheme == .dark ? .bold : .semibold))
            }
            .foregroundStyle(Tokens.joinFg)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settings.theme.accents.joinBg)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1.0)
        .clickCursor()
    }
}

/// The fallback "no hero" line shown when there's no event in the next 60
/// minutes but there's still something later today. Tapping it toggles the
/// referenced meeting's agenda row (the expansion state is lifted into
/// `MenuBarContentView.expandedEventIDs`), so the line leads somewhere
/// instead of being inert text.
private struct NoUpNextLine: View {
    let next: MeetingEvent
    @Binding var expanded: Bool
    @State private var hovering = false
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(lm.t("popover.nothingSoon", next.startTimeString))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tokens.ink2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.ink4)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.18), value: expanded)
                    .transaction { $0.disablesAnimations = false }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Tokens.paper2 : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickCursor()
        .accessibilityLabel(lm.t("popover.nothingSoon", next.startTimeString))
        .accessibilityHint(next.title)
    }
}

// MARK: - Section label & agenda row

private struct SectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Tokens.ink3)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Tokens.paper3))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

private struct AgendaRow: View {
    let event: MeetingEvent
    let dimmed: Bool
    /// Non-nil for reminder rows — tapping the circle icon completes the
    /// reminder and removes it from the list. Nil for meeting rows (no-op).
    let onComplete: (() -> Void)?
    /// Lifted to `MenuBarContentView.expandedEventIDs` (was a local `@State`)
    /// so `NoUpNextLine` can expand a row from outside. Behavior within the
    /// row is unchanged — the expand/collapse Button toggles this binding.
    @Binding var expanded: Bool
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        // Resolve @MainActor-isolated joinURL once here so child views can
        // receive it as a plain URL? without needing @MainActor themselves.
        let joinURL = event.joinURL
        let hasContent = !event.calendarTitle.isEmpty
            || (event.location.map { !$0.isEmpty } ?? false)
            || !event.attendees.isEmpty
            || joinURL != nil

        VStack(spacing: 0) {
            // MARK: Row header (always visible)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.startTimeString)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(dimmed ? Tokens.ink4 : Tokens.ink3)
                    .frame(width: 52, alignment: .leading)

                // Reminder-complete toggle: a real, standalone Button (a
                // sibling of the expand/collapse Button below, not nested
                // inside it) so VoiceOver and keyboard focus can reach both
                // controls independently — SwiftUI buttons nested inside
                // other buttons lose their individual accessibility actions.
                if event.isReminder {
                    if let onComplete {
                        Button(action: onComplete) {
                            Image(systemName: dimmed ? "checkmark.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(dimmed ? Tokens.ink4 : Tokens.ink3)
                                // Widen the hit area to ~24pt without moving
                                // the glyph: pad, capture the padded bounds as
                                // the hit shape, then un-pad the layout. A bare
                                // 12pt icon was too small a click target.
                                .padding(6)
                                .contentShape(Rectangle())
                                .padding(-6)
                        }
                        .buttonStyle(.plain)
                        .clickCursor()
                        .accessibilityLabel(dimmed ? lm["alert.action.complete"] : lm["popover.reminder"])
                    } else {
                        Image(systemName: dimmed ? "checkmark.circle" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(dimmed ? Tokens.ink4 : Tokens.ink3)
                    }
                }

                // Expand/collapse control. A real Button (rather than the
                // previous whole-row onTapGesture) so VoiceOver announces it
                // as an actionable control and keyboard/Tab focus can reach
                // it — the row wasn't reachable by either before.
                Button {
                    guard hasContent else { return }
                    expanded.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .medium))
                                .tracking(-0.1)
                                .foregroundStyle(dimmed ? Tokens.ink4 : Tokens.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(metaText)
                                .font(.system(size: 11))
                                .foregroundStyle(Tokens.ink3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)

                        // Chevron — only shown when there's something to reveal.
                        // Rotates 90° when expanded; animation is scoped so it runs
                        // even while the parent's disablesAnimations transaction is on.
                        if hasContent {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Tokens.ink4)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .animation(.easeInOut(duration: 0.18), value: expanded)
                                .transaction { $0.disablesAnimations = false }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasContent)
                .clickCursor()
                .accessibilityLabel("\(event.title), \(metaText)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            // MARK: Expanded detail panel (instant open — no content animation)
            if expanded {
                AgendaRowDetailPanel(event: event, dimmed: dimmed, joinURL: joinURL)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        // When expanded: card background with border.
        // When collapsed + hovering: subtle fill as hover affordance.
        .background(
            ZStack {
                if expanded {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Tokens.paper2)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Tokens.line, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering && hasContent ? Tokens.paper2 : Color.clear)
                }
            }
            .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .padding(.vertical, expanded ? 2 : 0)
    }

    /// "30m · Olympos · Muhammed, Eren" — only segments with content render.
    /// For reminders this collapses to "Reminder" (+ optional notes preview).
    private var metaText: String {
        if event.isReminder {
            return event.rawDetails.isEmpty
                ? lm["popover.reminder"]
                : lm.t("popover.reminderWithDetails", event.rawDetails)
        }
        var parts: [String] = [event.durationString(lm: lm)]
        if let loc = event.location, !loc.isEmpty {
            parts.append(loc)
        }
        if !event.attendees.isEmpty {
            let visible = event.attendees.prefix(2).joined(separator: ", ")
            let extra = event.attendees.count - 2
            parts.append(extra > 0 ? "\(visible)…" : visible)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Agenda row detail panel

/// Expanded content shown below an `AgendaRow` header when the user taps it.
/// Displays calendar identity, full time range, location, attendees, and (for
/// upcoming meetings) a Join button. Receives `joinURL` as a plain `URL?`
/// rather than calling `event.joinURL` itself — the caller resolves the
/// `@MainActor`-isolated property and passes the result in.
private struct AgendaRowDetailPanel: View {
    let event: MeetingEvent
    let dimmed: Bool
    let joinURL: URL?
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Calendar identity: color dot + name
            if !event.calendarTitle.isEmpty {
                HStack(spacing: 5) {
                    if let c = event.calendarColor {
                        Circle()
                            .fill(Color(red: c.red, green: c.green,
                                        blue: c.blue, opacity: c.alpha))
                            .frame(width: 7, height: 7)
                    }
                    Text(event.calendarTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.ink3)
                        .lineLimit(1)
                }
            }

            // Full time range (suppressed for reminders — they're instant)
            if !event.isReminder {
                Text("\(event.timeRangeString) · \(event.durationString(lm: lm))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Tokens.ink2)
            }

            // Location
            if let loc = event.location, !loc.isEmpty {
                AgendaDetailMetaLine(systemImage: "mappin.circle.fill", text: loc)
            }

            // Attendees (up to 3, then +N overflow)
            if !event.attendees.isEmpty {
                let shown = event.attendees.prefix(3).joined(separator: ", ")
                let extra = event.attendees.count - 3
                let text = extra > 0 ? "\(shown) +\(extra)" : shown
                AgendaDetailMetaLine(systemImage: "person.2.fill", text: text)
            }

            // Join button — only for upcoming (non-dimmed) events
            if let url = joinURL, !dimmed {
                JoinButton(
                    url: url,
                    scheme: scheme,
                    authUser: settings.authUser(forCalendarID: event.calendarID)
                )
                .padding(.top, 2)
            }

            // "Open in Calendar" — only meaningful for events that actually
            // have a native Calendar.app entry (EventKit meetings; not
            // reminders, not Graph/Exchange events, which live server-side).
            if let eventID = event.eventKitIdentifier {
                Button {
                    MeetingURLOpener.openInCalendar(eventIdentifier: eventID)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(lm["popover.openInCalendar"])
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Tokens.ink3)
                }
                .buttonStyle(.plain)
                .clickCursor()
                .padding(.top, joinURL != nil && !dimmed ? 4 : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Icon + text row used inside `AgendaRowDetailPanel`. Uses neutral ink colors
/// rather than the amber `heroMeta` token that `MetaLine` uses for the hero card.
private struct AgendaDetailMetaLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.ink3)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.ink2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    let onPreferences: () -> Void
    let onQuit: () -> Void
    /// Nil in contexts where presenting mode isn't relevant yet (the
    /// onboarding stub) — the toggle simply doesn't render.
    var presentingModeEnabled: Bool? = nil
    var onTogglePresenting: (() -> Void)? = nil
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        HStack(spacing: 8) {
            FooterButton(systemImage: "gearshape", title: lm["popover.prefs"], action: onPreferences)
            if let presentingModeEnabled, let onTogglePresenting {
                PresentingToggleButton(isOn: presentingModeEnabled, action: onTogglePresenting)
            }
            Spacer(minLength: 0)
            FooterButton(systemImage: nil, title: lm["popover.quit"], action: onQuit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .top) {
                Tokens.paper2
                Rectangle().fill(Tokens.line).frame(height: 1)
            }
        )
    }
}

/// Manual "Presenting Now" toggle — see `AlertScheduler.presentingModeEnabled`.
/// Quiet gray pill when off (matches the other footer buttons); fills with
/// the brand accent when on, so the user can't forget it's active from a
/// glance at the popover. The label is always visible (not just when on) —
/// an icon alone didn't read as a toggle for "presenting mode" at a glance.
private struct PresentingToggleButton: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "rectangle.inset.filled" : "rectangle.on.rectangle")
                    .font(.system(size: 12))
                Text(lm["popover.presentingMode"])
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Tokens.joinFg : Tokens.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? settings.theme.accents.pulseDot : Color.secondary.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickCursor()
        .help(lm["statusMenu.presentingNow"])
    }
}

private struct FooterButton: View {
    let systemImage: String?
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                }
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Tokens.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .clickCursor()
    }
}

// MARK: - Menu bar label
//
// The status-item content (icon + optional "Title · in 12m"). Lives at the
// bottom of this file because it doesn't depend on any of the popover views.

/// A standalone clock that emits the current `Date` every 15 seconds. Lives
/// on its own so the menu bar label can hold it via `@StateObject`, which
/// SwiftUI preserves across struct re-instantiations. The previous
/// implementation used `let timer = Timer.publish(...)` as a struct property,
/// which got reset every time the parent re-rendered — meaning the timer
/// could be repeatedly torn down before its 30-second tick ever arrived,
/// leaving the menu bar minute-counter stale for whole minutes at a time.
@MainActor
final class TickClock: ObservableObject {
    @Published var date = Date()
    private var timer: Timer?

    init(interval: TimeInterval = 15) {
        // NOT `Timer.scheduledTimer`: that enrolls in the `.default` runloop
        // mode, which is throttled by App Nap and suspended during menu/event
        // tracking — the menu bar minute counter would freeze while a menu is
        // open. `.common` mode keeps ticking (same pattern as AlertScheduler).
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.date = Date()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }
}

/// Custom menu bar status item content. Shows the bell icon plus, when an
/// active or imminent meeting is on the schedule, the meeting title and a
/// compact time-to-go marker like "in 12m" or "20m left".
///
/// The 15-second tick cadence (driven by `TickClock`) keeps the minute
/// counter and the 5-minute lookahead transition snappy. The clock is held
/// via `@StateObject` so it survives the struct re-inits SwiftUI does on
/// every parent re-render.
struct MenuBarLabel: View {
    @ObservedObject var aggregator: CalendarAggregator
    @ObservedObject var scheduler: AlertScheduler
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var lm: LocalizationManager

    @StateObject private var clock = TickClock()

    /// Lets us auto-surface the onboarding window on first launch. The
    /// MenuBarExtra label is the earliest SwiftUI view that receives a
    /// `.task`, so this is the right place to trigger the welcome.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // MenuBarExtra hands the label View to NSStatusItem, which decomposes
        // it into the button's image and title slots. It applies its own
        // imagePosition (.imageLeading), so an HStack of [Image, Text] is the
        // ordering that survives — icon on the left, text on the right.
        Group {
            if scheduler.presentingModeEnabled {
                // Presenting Now overrides the normal label unconditionally
                // (even if "show meeting in menu bar" is off) — the whole
                // point is that the user can't forget it's suppressing
                // overlays while it's on.
                HStack(spacing: 4) {
                    Self.menuBarLogoImage
                    Text(lm["menubar.presenting"])
                }
            } else if settings.showNextMeetingInMenuBar,
               let meeting = scheduler.currentMenuBarMeeting(now: clock.date) {
                HStack(spacing: 4) {
                    Self.menuBarLogoImage
                    Text("\(displayTitle(for: meeting)) · \(timeLabel(for: meeting, now: clock.date))")
                }
            } else {
                Self.menuBarLogoImage
            }
        }
        .onAppear { syncStatusMenu() }
        .onChange(of: clock.date) { _, _ in syncStatusMenu() }
        .task {
            // Run the same bootstrap the popover does, but at app launch
            // rather than first popover open — otherwise the menu bar label
            // can't compute the current meeting because the scheduler hasn't
            // wired up to the aggregator yet. Both calls are idempotent.
            await aggregator.start(
                enabledEventKitCalendars: settings.enabledEventKitCalendarIDs,
                enabledGraphCalendars: settings.enabledGraphCalendarIDs
            )
            scheduler.attach(aggregator: aggregator, settings: settings, lm: lm)

            // Auto-surface the onboarding window on first launch. The
            // `Window` scene declared on the App registers itself before
            // any view's task runs, so `openWindow(id:)` is safe here. We
            // also activate the app so the window comes to the front
            // (otherwise the window can spawn but stay behind whatever the
            // user was looking at).
            if !settings.onboardingCompleted {
                openWindow(id: WindowID.onboarding)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Loads the `MenuBarIcon` image asset as a SwiftUI view.
    ///
    /// How to add your logo:
    ///  1. In Xcode, open Assets.xcassets.
    ///  2. Press + → New Image Set, name it exactly `MenuBarIcon`.
    ///  3. Drop a monochrome (transparent background) PNG into the 1× and 2×
    ///     slots (18×18 px and 36×36 px) or a single PDF/SVG into "Universal".
    ///  4. In the asset inspector, set Render As → Template Image so it
    ///     adapts automatically to light / dark mode and the active-highlight
    ///     state of the status item.
    ///
    /// Until the asset exists the app falls back to a plain bell icon.
    private static let menuBarLogoImage: some View = {
        if let img = NSImage(named: "MenuBarIcon") {
            // Custom asset found — treat it as a template so it adapts to
            // light/dark mode automatically. The asset should be monochrome
            // with a transparent background; a colorful or backgrounded image
            // will look wrong as a template.
            img.isTemplate = true
            return AnyView(
                Image(nsImage: img)
                    .renderingMode(.template)
            )
        } else {
            // Fallback: a native SF Symbol bell that looks at home in the
            // menu bar. Remove or replace the MenuBarIcon asset to use this.
            return AnyView(Image(systemName: "bell.fill"))
        }
    }()

    /// Keep StatusMenuController in sync so right-click context menu shows the
    /// correct meeting title and hide action. Called on every clock tick and on
    /// first appearance so the controller is never stale.
    private func syncStatusMenu() {
        let meeting = scheduler.currentMenuBarMeeting(now: clock.date)
        StatusMenuController.shared.currentMeetingTitle = meeting?.title
        StatusMenuController.shared.onHideMeeting = meeting.map { m in
            { scheduler.muteFromMenuBar(m.id) }
        }
        StatusMenuController.shared.presentingModeEnabled = scheduler.presentingModeEnabled
        StatusMenuController.shared.onTogglePresenting = { scheduler.togglePresentingMode() }
    }

    /// Truncate long titles so the menu bar doesn't overflow on small screens.
    private func displayTitle(for meeting: MeetingEvent) -> String {
        let max = 28
        guard meeting.title.count > max else { return meeting.title }
        return String(meeting.title.prefix(max - 1)) + "…"
    }

    private func timeLabel(for meeting: MeetingEvent, now: Date) -> String {
        let untilStart = meeting.startDate.timeIntervalSince(now)

        // Reminders are an instant in time — there's no "Xm left" because
        // they have no duration. Show "in Xm" when approaching, "due now"
        // around the moment, and "Xm ago" once overdue.
        if meeting.isReminder {
            if untilStart > 30 {
                let mins = max(1, Int((untilStart + 30) / 60))
                return lm.t("menubar.inMinutes", mins)
            } else if untilStart > -60 {
                return lm["menubar.dueNow"]
            } else {
                let mins = max(1, Int((-untilStart + 30) / 60))
                return lm.t("menubar.minutesAgo", mins)
            }
        }

        let untilEnd = meeting.endDate.timeIntervalSince(now)
        if untilStart > 0 {
            // Round up so 30–89 sec shows as "1m" rather than "0m".
            let mins = max(1, Int((untilStart + 30) / 60))
            return lm.t("menubar.inMinutes", mins)
        } else {
            let mins = max(1, Int((untilEnd + 30) / 60))
            return lm.t("menubar.left", mins)
        }
    }
}
