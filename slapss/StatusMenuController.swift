//
//  StatusMenuController.swift
//  slapss
//
//  Manages the right-click context menu on the menu bar status item.
//
//  Strategy: instead of trying to look up the NSStatusItem (whose API is
//  private), we monitor local rightMouseDown events and check whether the
//  event's host window sits inside the macOS menu bar strip. We compare
//  the window's vertical midpoint against the bottom of the menu bar using
//  NSStatusBar.system.thickness — a public API — so no private class names
//  are inspected. Since slapss has exactly one status item, any right-click
//  from a window in that position must be ours.
//

import AppKit

final class StatusMenuController {
    static let shared = StatusMenuController()

    /// Title of the meeting currently pinned to the menu bar, if any.
    var currentMeetingTitle: String?

    /// Called when the user chooses "Hide … from menu bar" in the context menu.
    var onHideMeeting: (() -> Void)?

    /// Called when the user chooses "Preferences" in the context menu.
    /// Set from MenuBarContentView so we can call SwiftUI's openSettings action.
    var onOpenPreferences: (() -> Void)?

    /// Called when the user toggles "Presenting Now" in the context menu.
    /// Set from `MenuBarLabel.syncStatusMenu()`.
    var onTogglePresenting: (() -> Void)?

    /// Mirrors `AlertScheduler.presentingModeEnabled` so the menu item shows
    /// the correct checkmark state. Kept in sync from `syncStatusMenu()`.
    var presentingModeEnabled = false

    /// Localization source for the menu's strings. Weak because it's owned by
    /// the SwiftUI `slapssApp` for the app's lifetime — this singleton only
    /// borrows it, it doesn't need to keep it alive.
    weak var lm: LocalizationManager?

    private var eventMonitor: Any?

    private init() {}

    // MARK: - Setup

    func setup() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleIfOnStatusBar(event: event) ?? event
        }
    }

    // MARK: - Event handling

    private func handleIfOnStatusBar(event: NSEvent) -> NSEvent? {
        // Identify the status-bar window by position rather than by its
        // private class name. The system menu bar occupies the topmost strip
        // of the screen; any window whose vertical midpoint sits inside that
        // strip must be a status-item host window. NSStatusBar.system.thickness
        // and NSScreen.frame are both public API.
        guard let window = event.window,
              let screen = window.screen ?? NSScreen.main
        else { return event }

        let menuBarMinY = screen.frame.maxY - NSStatusBar.system.thickness - 4
        guard window.frame.midY >= menuBarMinY else { return event }

        showContextMenu(event: event, in: window)
        return nil // consume — prevent the default no-op right-click behaviour
    }

    // MARK: - Context menu

    private func showContextMenu(event: NSEvent, in window: NSWindow) {
        let menu = NSMenu()

        if let title = currentMeetingTitle, onHideMeeting != nil {
            let display = title.count > 30
                ? String(title.prefix(29)) + "…"
                : title
            let hideItem = NSMenuItem(
                title: hideMeetingTitle(for: display),
                action: #selector(hideMeeting),
                keyEquivalent: ""
            )
            hideItem.target = self
            menu.addItem(hideItem)
            menu.addItem(.separator())
        }

        if onTogglePresenting != nil {
            let presentingItem = NSMenuItem(
                title: localized("statusMenu.presentingNow", fallback: "Presenting Now"),
                action: #selector(togglePresenting),
                keyEquivalent: ""
            )
            presentingItem.target = self
            presentingItem.state = presentingModeEnabled ? .on : .off
            menu.addItem(presentingItem)
            menu.addItem(.separator())
        }

        let prefsItem = NSMenuItem(
            title: localized("popover.prefs", fallback: "Preferences"),
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localized("statusMenu.quit", fallback: "Quit Slapss"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // popUpContextMenu positions the menu relative to the event location,
        // which is exactly where the user right-clicked on the status item.
        NSMenu.popUpContextMenu(menu, with: event, for: window.contentView ?? NSView())
    }

    // MARK: - Localization helpers

    /// Resolves a string through the borrowed `LocalizationManager`, falling
    /// back to the English literal if the manager isn't wired up yet (e.g. a
    /// right-click landing before the popover's first appearance).
    private func localized(_ key: String, fallback: String) -> String {
        guard let lm else { return fallback }
        return lm[key]
    }

    private func hideMeetingTitle(for meetingName: String) -> String {
        guard let lm else { return "Hide \"\(meetingName)\" from menu bar" }
        return lm.t("popover.hideFromMenuBar", meetingName)
    }

    // MARK: - Actions

    @objc private func hideMeeting() {
        onHideMeeting?()
    }

    @objc private func togglePresenting() {
        onTogglePresenting?()
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Cleanup

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
