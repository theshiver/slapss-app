//
//  AlertView.swift
//  slapss
//
//  Full-screen "Wide Hero" alert. Mesh-gradient backdrop, glass card, two
//  columns: meeting metadata on the left, action stack on the right.
//
//  States:
//   - upcoming: meeting starts in > 1 minute
//   - imminent: meeting starts in ≤ 1 minute
//   - live:     meeting started ≤ 5 minutes ago
//   - late:     meeting started > 5 minutes ago
//
//  The state drives the status pill, the dot animation, and the mesh palette.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Alert state

enum AlertState {
    case upcoming
    case imminent
    case live
    case late

    static func compute(now: Date, start: Date) -> AlertState {
        let interval = start.timeIntervalSince(now)
        if interval > 60 { return .upcoming }
        if interval > 0 { return .imminent }
        if interval > -300 { return .live }
        return .late
    }

    func statusLabel(now: Date, start: Date, lm: LocalizationManager) -> String {
        let interval = start.timeIntervalSince(now)
        let absMin = max(0, Int(abs(interval) / 60))
        switch self {
        case .upcoming:
            return lm.t("alert.status.inMinutes", absMin)
        case .imminent:
            let secs = max(0, Int(interval))
            return secs > 5 ? lm.t("alert.status.inSeconds", secs) : lm["alert.status.anyMoment"]
        case .live:
            return absMin == 0 ? lm["alert.status.startedJustNow"] : lm.t("alert.status.startedMinutesAgo", absMin)
        case .late:
            return lm.t("alert.status.youAreLateMinutes", absMin)
        }
    }

    enum DotKind { case none, live, urgent }
    var dotKind: DotKind {
        switch self {
        case .upcoming, .imminent: return .none
        case .live: return .live
        case .late: return .urgent
        }
    }

    // NOTE (theming): the backdrop palette is no longer derived from the alert
    // state — it comes from the user's theme (AppTheme.meshPalette), passed
    // into AlertView explicitly. The original v1 idea of per-state palettes
    // (urgent = all-reds) was abandoned because it flattened out the scene;
    // state still drives the dot color and label.
}

// MARK: - AlertView

struct AlertView: View {
    let meeting: MeetingEvent
    /// User-selected color theme — drives the mesh backdrop palette. Passed
    /// explicitly (not via environment) because the overlay's NSHostingView
    /// doesn't inherit SwiftUI environment objects, and AlertScheduler only
    /// holds AppSettings weakly. Captured at fire time; a theme change while
    /// an overlay is on screen applies from the next alert on.
    let theme: AppTheme
    let onJoin: () -> Void
    /// Non-nil only when the meeting is a reminder. Shows the Complete button
    /// instead of the Join button. Marks the EKReminder complete and dismisses.
    let onComplete: (() -> Void)?
    let onDismiss: () -> Void
    let onSnoozeMinutes: (Int) -> Void
    let onSnoozeUntilEnd: () -> Void

    @EnvironmentObject private var lm: LocalizationManager

    @State private var tick = Date()
    @State private var snoozeOpen = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var state: AlertState {
        AlertState.compute(now: tick, start: meeting.startDate)
    }

    /// Themed accent set for the overlay CTA. Read from the passed-in theme
    /// (not the environment) — see the `theme` property note above.
    private var accents: AppTheme.Accents { theme.accents }

    var body: some View {
        ZStack {
            MeshBackground(palette: theme.meshPalette)

            // Subtle ambient vignette so the screen edges aren't quite as bright
            // as the center where the card sits. Much lighter than a "dim" —
            // we want the mesh colors to remain prominent.
            RadialGradient(
                colors: [.clear, .black.opacity(0.25)],
                center: .center,
                startRadius: 300,
                endRadius: 1400
            )
            .blendMode(.multiply)
            .ignoresSafeArea()

            card
                .frame(maxWidth: 880)
                .padding(56)
        }
        // Always fill the whole screen and ignore the safe area (notch / menu
        // bar) so the centred card stays centred. Without this the root can
        // collapse toward the card's intrinsic size and the card drifts into a
        // corner while the mesh/vignette (which ignore the safe area) still
        // cover the screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onReceive(timer) { tick = $0 }
    }

    // MARK: - Card

    private var card: some View {
        HStack(alignment: .center, spacing: 56) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1.1)
            rightColumn
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 400)
                .layoutPriority(1.0)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 56)
        .background(glassBackground)
        .overlay(glassBorder)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.55), radius: 80, x: 0, y: 30)
    }

    /// Liquid-glass effect.
    ///
    /// We previously tried `.menu` material + a flat dark overlay — the result
    /// looked uniformly frosted-gray because the material desaturated the mesh
    /// colors below. `.fullScreenUI` keeps more of the warm tones bleeding
    /// through, and dropping the flat dark overlay (relying on the material's
    /// own translucency) lets the orange/purple mesh tint the surface.
    /// A top inner highlight + a faint top-to-bottom dark gradient gives the
    /// "light hits the top bevel" specular feel.
    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            // Reduce Transparency is on — skip the material entirely and use
            // a flat, high-contrast fill. `VisualEffectView` blends with
            // whatever's behind it regardless of this accessibility setting,
            // so honoring it means not routing through NSVisualEffectView at
            // all rather than trying to tune its opacity.
            Color(rgb: 0x1c1a22)
        } else {
            ZStack {
                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)

                // Subtle top-to-bottom darkening — keeps text contrast without
                // washing the whole card gray.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.05),
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top specular highlight — strongest at the top edge, fades by
                // ~40% down the card.
                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.4)
                )
            }
        }
    }

    /// Glass edge: brighter on top, dimmer at the bottom — mimics light hitting
    /// the top bevel of a real glass surface.
    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 32)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.30),
                        Color.white.opacity(0.05),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            statePill
            title
            timeRow
            metaRow
        }
    }

    private var statePill: some View {
        HStack(spacing: 10) {
            stateDot
            // "MEETING · IN 5 MIN" for calendar events, "REMINDER · …" for
            // EKReminders. Previously every alert said "REMINDER", which
            // collided with the app's actual Reminders support.
            Text("\(lm[meeting.isReminder ? "alert.status.reminder" : "alert.status.meeting"]) · \(state.statusLabel(now: tick, start: meeting.startDate, lm: lm).uppercased())")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var stateDot: some View {
        switch state.dotKind {
        case .none:
            EmptyView()
        case .live:
            PulsingDot(color: Color(rgb: 0x2da14a))
        case .urgent:
            PulsingDot(color: Color(rgb: 0xe8633a))
        }
    }

    private var title: some View {
        Text(meeting.title)
            .font(.system(size: 56, weight: .semibold))
            .tracking(-2)
            .foregroundStyle(.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var timeRow: some View {
        Group {
            if meeting.isReminder {
                // Reminders have startDate == endDate — showing a range
                // would render "14:00 – 14:00". Show "Due at HH:MM" instead.
                Text(lm.t("alert.dueAt", timeString(meeting.startDate)))
                    .monospacedDigit()
            } else {
                HStack(spacing: 14) {
                    Text(timeString(meeting.startDate))
                        .monospacedDigit()
                    Rectangle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 18, height: 1)
                    Text(timeString(meeting.endDate))
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            if let location = meeting.location, !location.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13))
                    Text(location)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.55))
            }

            if !meeting.attendees.isEmpty {
                if meeting.location != nil && !meeting.location!.isEmpty {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 3, height: 3)
                }
                HStack(spacing: 8) {
                    AvatarStack(names: Array(meeting.attendees.prefix(4)))
                    if meeting.attendees.count > 4 {
                        Text("+ \(meeting.attendees.count - 4)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 14) {
            if meeting.isReminder {
                completeButton
            } else {
                joinButton
            }
            actionsRow
            keyboardHint
        }
    }

    /// Discoverability line for the overlay's keyboard shortcuts (ESC and
    /// Return are wired in `OverlayWindow` but were invisible). Reuses the
    /// action labels so no extra localization keys are needed. The ↩ half
    /// only renders when Return actually has a visible counterpart button.
    private var keyboardHint: some View {
        let primaryLabel: String? = meeting.isReminder
            ? lm["alert.action.complete"]
            : (meeting.joinURL != nil ? lm["alert.join.generic"] : nil)
        return HStack(spacing: 14) {
            if let primaryLabel {
                Text("↩ \(primaryLabel)")
            }
            Text("esc \(lm["alert.action.dismiss"])")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
        .padding(.top, 2)
    }

    /// Complete button — shown for EKReminder overlays in place of the Join button.
    @ViewBuilder
    private var completeButton: some View {
        if let onComplete {
            Button(action: onComplete) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text(lm["alert.action.complete"])
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [accents.overlayCtaTop, accents.overlayCtaBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: accents.overlayCtaTop.opacity(0.6), radius: 20, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .clickCursor()
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        if meeting.joinURL != nil {
            Button(action: onJoin) {
                HStack {
                    HStack(spacing: 10) {
                        platformBadge
                        Text(joinLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [accents.overlayCtaTop, accents.overlayCtaBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: accents.overlayCtaTop.opacity(0.6), radius: 20, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .clickCursor()
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            // Keep the snooze choices inside the full-screen overlay's own
            // view hierarchy. A native SwiftUI popover is hosted in a separate
            // system window, which can be suppressed behind our borderless
            // `.screenSaver`-level window on macOS 27.
            Button { snoozeOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 14))
                    Text(lm["alert.action.snooze"])
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(snoozeOpen ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(.easeOut(duration: 0.16), value: snoozeOpen)
            .frame(maxWidth: .infinity)

            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                    Text(lm["alert.action.dismiss"])
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .clickCursor()
        }
        .overlay(alignment: .bottomLeading) {
            if snoozeOpen {
                snoozeDropdown
                    .offset(y: -58)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .bottomLeading)
                        )
                    )
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.16), value: snoozeOpen)
    }

    // MARK: - Snooze dropdown

    private var snoozeDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lm["alert.snooze.header"])
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            snoozeOption(label: lm["alert.snooze.1minute"])  { onSnoozeMinutes(1);  snoozeOpen = false }
            snoozeOption(label: lm["alert.snooze.5minutes"]) { onSnoozeMinutes(5);  snoozeOpen = false }
            snoozeOption(label: lm["alert.snooze.10minutes"]){ onSnoozeMinutes(10); snoozeOpen = false }
            snoozeOption(label: lm["alert.snooze.15minutes"]){ onSnoozeMinutes(15); snoozeOpen = false }
            // "Until end of meeting" doesn't apply to reminders — they're
            // an instant in time with no duration (startDate == endDate).
            if !meeting.isReminder {
                Divider().padding(.vertical, 4)
                snoozeOption(label: lm["alert.snooze.untilEnd"]) { onSnoozeUntilEnd(); snoozeOpen = false }
            }
        }
        .padding(6)
        .frame(width: 240)
        .background(
            Color(rgb: 0x1c1a22).opacity(0.98),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 10)
    }

    private func snoozeOption(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    // MARK: - Platform detection

    private var platformBadge: some View {
        let url = meeting.joinURL?.absoluteString.lowercased() ?? ""
        let color: Color
        if url.contains("zoom.us") { color = Color(rgb: 0x3a8ad0) }
        else if url.contains("teams.microsoft") || url.contains("teams.live") { color = Color(rgb: 0x6b6cd0) }
        else if url.contains("meet.google") { color = Color(rgb: 0x3aa86b) }
        else { color = Color(rgb: 0x888888) }

        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(color)
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    private var joinLabel: String {
        let url = meeting.joinURL?.absoluteString.lowercased() ?? ""
        if url.contains("zoom.us") { return lm["alert.join.zoom"] }
        if url.contains("teams.microsoft") || url.contains("teams.live") { return lm["alert.join.teams"] }
        if url.contains("meet.google") { return lm["alert.join.meet"] }
        if url.contains("webex.com") { return lm["alert.join.webex"] }
        return lm["alert.join.generic"]
    }

    // MARK: - Time formatting

    /// Respects the user's 12/24-hour preference from System Settings.
    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Cursor + hover helpers (module-internal so the menu bar popover can reuse them)

extension View {
    /// Shows the pointing-hand "click" cursor while the mouse is over the view.
    /// macOS 15+ uses the native `pointerStyle(.link)`. Older versions fall
    /// back to driving NSCursor manually on hover transitions.
    @ViewBuilder
    func clickCursor() -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(.link)
        } else {
            self.onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }

    /// Subtle rounded background that fades in while hovered. Useful for
    /// plain (chromeless) buttons in the menu bar popover where a regular
    /// button border would look heavy — gives users a hover affordance
    /// without changing the resting layout. Caller is responsible for any
    /// padding inside the highlighted area.
    func hoverBackground(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverBackground(cornerRadius: cornerRadius))
    }
}

private struct HoverBackground: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(hovering ? 0.12 : 0))
            )
            .onHover { hovering = $0 }
    }
}

// MARK: - Pulsing dot

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Group {
                    // Pulsing ring — hidden when Reduce Motion is enabled.
                    if !reduceMotion {
                        Circle()
                            .stroke(color.opacity(0.6), lineWidth: 2)
                            .scaleEffect(pulse ? 2.5 : 1)
                            .opacity(pulse ? 0 : 1)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)
                    }
                }
            )
            .onAppear { if !reduceMotion { pulse = true } }
    }
}

// MARK: - Avatar stack

private struct AvatarStack: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Avatar(
                    initials: Self.initials(from: name),
                    hue: Self.hue(for: name),
                    fullName: name
                )
            }
        }
    }

    /// Two-character initials from a display name. Falls back to first letter
    /// of an email's local part if the name is blank.
    static func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        // If it looks like an email, use the local part for initials.
        let source: String
        if trimmed.contains("@") {
            source = trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        } else {
            source = trimmed
        }
        let parts = source.split(whereSeparator: { " ._-".contains($0) }).prefix(2)
        let chars = parts.compactMap { $0.first }
        return String(chars).uppercased()
    }

    /// Deterministic hue 0..360 from the name string so the same person gets
    /// the same color across renders.
    static func hue(for name: String) -> Double {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360)
    }
}

private struct Avatar: View {
    let initials: String
    let hue: Double
    let fullName: String

    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hue: hue / 360, saturation: 0.5, brightness: 0.55))
            Text(initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay(
            Circle()
                .stroke(Color(rgb: 0x141416), lineWidth: 2)
        )
        .contentShape(Circle())
        .scaleEffect(hovering ? 1.1 : 1.0)
        .zIndex(hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        // The name tooltip below is hover-only (system tooltips are
        // suppressed in screen-saver-level windows) — expose it directly to
        // VoiceOver so keyboard/screen-reader users aren't left with just
        // two-letter initials.
        .accessibilityLabel(fullName)
        // Custom in-window tooltip. macOS system tooltips (.help) suppress
        // themselves in borderless `.screenSaver`-level windows, so we render
        // our own as a SwiftUI overlay inside the alert.
        .overlay(alignment: .bottom) {
            if hovering {
                Text(fullName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.black.opacity(0.88))
                    )
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                    .offset(y: 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
    }
}
