//
//  slapssApp.swift
//  slapss
//
//  Slapss — your meeting, in your face.
//

import SwiftUI

@main
struct slapssApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var aggregator = CalendarAggregator()
    @StateObject private var settings = AppSettings()
    @StateObject private var scheduler = AlertScheduler()
    @StateObject private var lm = LocalizationManager()
    @StateObject private var popoverVisibility = PopoverVisibilityMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(aggregator)
                .environmentObject(settings)
                .environmentObject(scheduler)
                .environmentObject(lm)
                .environmentObject(popoverVisibility)
        } label: {
            MenuBarLabel(aggregator: aggregator, scheduler: scheduler, settings: settings)
                .environmentObject(lm)
        }
        .menuBarExtraStyle(.window)

        // Standalone onboarding window — only shown for first-launch users.
        // We intentionally render this as a real window (not inline in the
        // popover) because:
        //   1. The first-run flow needs more breathing room than a 360pt
        //      menu-bar popover can offer.
        //   2. Granting calendar access spawns a system permission sheet,
        //      and presenting it from a transient popover regularly
        //      misbehaves on macOS — the popover dismisses, taking the
        //      onboarding state with it.
        // `MenuBarLabel.task` opens this window automatically on first
        // launch; `OnboardingView` dismisses it via `dismissWindow`.
        Window("Welcome to Slapss", id: WindowID.onboarding) {
            OnboardingView()
                .environmentObject(aggregator)
                .environmentObject(settings)
                .environmentObject(scheduler)
                .environmentObject(lm)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 620)

        Settings {
            SettingsView()
                .environmentObject(aggregator)
                .environmentObject(settings)
                .environmentObject(lm)
        }
    }
}

/// Centralized identifiers for SwiftUI scenes that need to be referenced by
/// string from elsewhere in the app (e.g. `openWindow(id:)`).
enum WindowID {
    static let onboarding = "slapss.onboarding"
}
