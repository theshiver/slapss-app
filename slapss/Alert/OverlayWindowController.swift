//
//  OverlayWindowController.swift
//  slapss
//
//  The full-screen "in your face" alert window. Covers the entire screen, rises
//  above the menu bar and other apps (including those in fullscreen mode), and
//  appears across all Spaces.
//
//  Why not a SwiftUI Window scene: SwiftUI's window primitives don't expose
//  the screen-saver-level / collection-behavior knobs we need to be truly
//  "in your face." We host SwiftUI inside an NSWindow we configure manually.
//

import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    /// One window per target screen. A single-screen alert holds one entry;
    /// a mirrored alert holds one per connected display.
    private var windows: [OverlayWindow] = []

    /// Whoever was frontmost when the alert appeared, so we can return keyboard
    /// focus to them on dismiss instead of leaving the user's focus stranded.
    private var previousApp: NSRunningApplication?

    /// Observer for live display layout changes (plug/unplug, resolution
    /// change) so a mirrored alert reflows onto the new set of screens while
    /// it's still on screen.
    private var screenChangeObserver: NSObjectProtocol?

    /// Retained while an alert is visible so the screen-change observer can
    /// rebuild the windows from the same parameters.
    private var activePresentation: Presentation?

    /// Everything needed to (re)build the overlay windows.
    private struct Presentation {
        let meeting: MeetingEvent
        let onJoin: () -> Void
        /// Non-nil when the alert is for an EKReminder — shows the Complete
        /// button instead of Join.
        let onComplete: (() -> Void)?
        let onDismiss: () -> Void
        let onSnoozeMinutes: (Int) -> Void
        let onSnoozeUntilEnd: () -> Void
        let mirrorOnAllScreens: Bool
        let lm: LocalizationManager
        /// Color theme captured at fire time — see `AlertView.theme`.
        let theme: AppTheme
    }

    func show(
        meeting: MeetingEvent,
        onJoin: @escaping () -> Void,
        onComplete: (() -> Void)?,
        onDismiss: @escaping () -> Void,
        onSnoozeMinutes: @escaping (Int) -> Void,
        onSnoozeUntilEnd: @escaping () -> Void,
        mirrorOnAllScreens: Bool,
        lm: LocalizationManager,
        theme: AppTheme
    ) {
        let presentation = Presentation(
            meeting: meeting,
            onJoin: onJoin,
            onComplete: onComplete,
            onDismiss: onDismiss,
            onSnoozeMinutes: onSnoozeMinutes,
            onSnoozeUntilEnd: onSnoozeUntilEnd,
            mirrorOnAllScreens: mirrorOnAllScreens,
            lm: lm,
            theme: theme
        )

        // Remember the frontmost app only when an alert isn't already up, so a
        // mid-alert rebuild doesn't capture the overlay itself.
        if windows.isEmpty {
            previousApp = NSWorkspace.shared.frontmostApplication
        }

        activePresentation = presentation
        buildWindows(for: presentation)
        registerScreenChangeObserver()

        // Become active *and* key so the overlay actually receives the ESC
        // keypress. For a menu-bar (accessory / LSUIElement) app, a window can't
        // become key from `makeKeyAndOrderFront` alone unless the app itself is
        // active — that's why ESC previously only worked after a manual click on
        // the overlay. Activating is also fitting for a takeover alert, and no
        // Dock icon appears because the app stays an accessory.
        NSApp.activate(ignoringOtherApps: true)
        // The window on the primary screen becomes key (ESC target); the rest
        // just order front so they're visible on their displays.
        let keyWindow = windows.first(where: { $0.screen == NSScreen.main }) ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        windows.forEach { $0.orderFrontRegardless() }
    }

    func hide() {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        activePresentation = nil
        teardownWindows()

        // Hand keyboard focus back to whatever the user was in before the alert
        // grabbed it. macOS often does this for an accessory app with no other
        // windows, but restoring it explicitly avoids leaving the user with no
        // focused app after they dismiss.
        previousApp?.activate(options: [])
        previousApp = nil
    }

    // MARK: - Window lifecycle

    /// Build one overlay window per target screen, hosting a fresh AlertView in
    /// each. All windows share the same action closures, so dismissing/joining/
    /// snoozing on any screen runs the same callback — which calls `hide()` and
    /// tears every window down together.
    private func buildWindows(for presentation: Presentation) {
        teardownWindows()

        let allScreens = NSScreen.screens
        let targetScreens: [NSScreen] = presentation.mirrorOnAllScreens && !allScreens.isEmpty
            ? allScreens
            : [NSScreen.main].compactMap { $0 }

        for screen in targetScreens {
            let window = makeWindow(frame: screen.frame)

            let rootView = AlertView(
                meeting: presentation.meeting,
                theme: presentation.theme,
                onJoin: presentation.onJoin,
                onComplete: presentation.onComplete,
                onDismiss: presentation.onDismiss,
                onSnoozeMinutes: presentation.onSnoozeMinutes,
                onSnoozeUntilEnd: presentation.onSnoozeUntilEnd
            )

            // Host the SwiftUI tree in a view that always fills the window.
            //
            // `NSHostingView`'s default `sizingOptions` (`.standardBounds`) lets
            // the SwiftUI content drive the view's size. When the alert's root
            // collapsed toward its intrinsic (card-sized) bounds, the card was
            // laid out in a small corner frame while the mesh/vignette — which
            // ignore the safe area — kept bleeding to fill the screen. The
            // result was a centred backdrop with the card jammed top-right and
            // clipped off the edge. Clearing `sizingOptions` and pinning the
            // autoresizing mask forces the hosting view to track the full
            // window bounds.
            let hosting = NSHostingView(rootView: rootView.environmentObject(presentation.lm))
            hosting.sizingOptions = []
            window.contentView = hosting
            hosting.autoresizingMask = [.width, .height]
            window.setFrame(screen.frame, display: true)
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)

            // ESC dismisses the alert — route the window's cancel action to it.
            window.onCancel = presentation.onDismiss
            // Return/Enter triggers the primary action — Complete for
            // reminders, Join for meetings (which itself just dismisses if
            // there's no detected join URL, so this is always safe to wire).
            window.onPrimaryAction = presentation.onComplete ?? presentation.onJoin

            windows.append(window)
        }
    }

    /// Order out every window and release its SwiftUI hosting view. `orderOut`
    /// alone keeps the NSHostingView alive in `contentView`, which means
    /// AlertView's 1-second `Timer.publish` and MeshBackground's blur
    /// animations keep running off-screen — the dominant background CPU drain
    /// once the user had dismissed an alert. Nulling each `contentView`
    /// deallocates the SwiftUI tree so its timers cease.
    private func teardownWindows() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }

    /// Reflow the overlay if displays are added/removed or rearranged while the
    /// alert is up. Only relevant when mirroring across all screens, but cheap
    /// enough to keep wired for the single-screen case too (NSScreen.main may
    /// change). No-op if no alert is currently presented.
    private func registerScreenChangeObserver() {
        guard screenChangeObserver == nil else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let presentation = self.activePresentation else { return }
                self.buildWindows(for: presentation)
                let keyWindow = self.windows.first(where: { $0.screen == NSScreen.main }) ?? self.windows.first
                keyWindow?.makeKeyAndOrderFront(nil)
                self.windows.forEach { $0.orderFrontRegardless() }
            }
        }
    }

    // MARK: - Window factory

    private func makeWindow(frame: NSRect) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // Above almost everything, including other apps in fullscreen.
        window.level = .screenSaver

        // Show across all Spaces and on top of fullscreen apps.
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]

        return window
    }
}

// MARK: - Overlay window

/// Borderless `.screenSaver`-level window that can still become key so it can
/// capture the ESC keypress. A vanilla borderless `NSWindow` returns `false`
/// from `canBecomeKey`, which would route ESC to whatever app is active instead
/// of dismissing the alert.
final class OverlayWindow: NSWindow {
    var onCancel: (() -> Void)?
    /// Fired on Return/Enter — mirrors the card's primary button (Join or
    /// Complete) so users can act without reaching for the trackpad.
    var onPrimaryAction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit sends `cancelOperation(_:)` up the responder chain when the user
    /// presses ESC (or ⌘.) and nothing else handles it.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Belt-and-suspenders: if the hosting view swallows the keyDown without
    /// forwarding a cancel action, catch ESC (keyCode 53) and Return
    /// (keyCode 36) / numpad Enter (keyCode 76) here directly.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            onPrimaryAction?()
        default:
            super.keyDown(with: event)
        }
    }
}
