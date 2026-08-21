//
//  PopoverVisibilityMonitor.swift
//  slapss
//

import AppKit
import Combine

/// Tracks whether the MenuBarExtra popover is currently visible on screen.
///
/// ## The problem
/// `MenuBarExtra(.window)` keeps the SwiftUI view graph alive permanently.
/// `onAppear` fires once when the popover is first opened; `onDisappear`
/// never fires on close — the window hides but is not destroyed. Any view
/// that uses `onAppear/onDisappear` to start/stop `.repeatForever()`
/// animations will leave them running at 60 fps with nothing visible on
/// screen, driving the main thread through the Metal render pipeline and
/// burning ~40% CPU indefinitely.
///
/// ## The fix
/// This monitor observes the underlying NSWindow's `didBecomeKeyNotification`
/// (popover appeared) and `willCloseNotification` (popover dismissed) to
/// publish the real visibility state. Animation views subscribe via
/// `.onChange(of: popoverVisibility.isVisible)` rather than `onAppear/onDisappear`.
final class PopoverVisibilityMonitor: ObservableObject {
    @Published private(set) var isVisible = false

    private var observers: [NSObjectProtocol] = []

    init() {
        // Popover window becomes key when it appears on screen.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notif in
                guard let window = notif.object as? NSWindow,
                      Self.isMenuBarPopover(window) else { return }
                self?.isVisible = true
            }
        )
        // Popover window fires willClose when dismissed (click-outside or
        // programmatic close). The window still exists at this point, so
        // isMenuBarPopover can still identify it.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notif in
                guard let window = notif.object as? NSWindow,
                      Self.isMenuBarPopover(window) else { return }
                self?.isVisible = false
            }
        )
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private

    /// Identifies the MenuBarExtra popover window using the same heuristics
    /// as `ContentView.menuBarExtraWindows()`: borderless, above-normal level,
    /// top edge at or just below the system menu bar.
    private static func isMenuBarPopover(_ window: NSWindow) -> Bool {
        guard let screen = NSScreen.main else { return false }
        let menuBarBottom = screen.frame.maxY - NSStatusBar.system.thickness
        return !window.styleMask.contains(.titled)
            && window.level.rawValue > NSWindow.Level.normal.rawValue
            && window.frame.maxY <= menuBarBottom + 4
            && window.frame.maxY >= menuBarBottom - 60
    }
}
