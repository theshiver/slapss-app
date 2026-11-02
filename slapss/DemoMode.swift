//
//  DemoMode.swift
//  slapss
//
//  Debug-only harness for checking the UI by hand and for taking marketing
//  screenshots and video without a real calendar. Never compiled into
//  Release. All flags are launch arguments:
//
//    -SlapssDemoData [seconds]   Replace the calendar with a fixed, realistic
//                                day. The hero meeting starts `seconds` after
//                                launch (default 240). The real scheduler runs
//                                on it, so its overlay fires at that time too.
//                                Whenever the popover opens, prints
//                                `SLAPSS_POPOVER_WINDOW <id>` for
//                                `screencapture -o -l <id>`. Opening it takes
//                                a real click on the icon: see the note on
//                                `logPopoverWindow`.
//    -SlapssDemoOverlay [seconds]
//                                Show the full-screen alert for a synthetic
//                                meeting starting `seconds` after launch
//                                (default 70; negative = already live/late).
//
//    -SlapssDemoPopover          With -SlapssDemoData: also show the popover's
//                                content in a window under the menu bar, so
//                                it can be captured and recorded without a
//                                click. Real content, approximated chrome.
//
//    -SlapssDemoAppearance dark|light
//                                Force the app's appearance regardless of the
//                                system setting, for screenshots.
//
//  Theme and language need no flag: `-slapss.theme forest` and
//  `-slapss.appLanguage tr` override UserDefaults for that run.
//

#if DEBUG
import AppKit

@MainActor
enum DemoMode {
    static let args = ProcessInfo.processInfo.arguments

    /// Whether a flag is present, and the number that follows it, if any.
    /// Parsed by hand: UserDefaults' argument domain reads a negative value
    /// such as "-297" as the next flag and drops it.
    static func flag(_ name: String) -> (present: Bool, value: Double?) {
        guard let i = args.firstIndex(of: name) else { return (false, nil) }
        return (true, args.indices.contains(i + 1) ? Double(args[i + 1]) : nil)
    }

    static var isDataActive: Bool { flag("-SlapssDemoData").present }

    /// Any demo flag skips onboarding, so it doesn't sit in the screenshots.
    static var skipsOnboarding: Bool {
        isDataActive || flag("-SlapssDemoOverlay").present
    }

    static func startIfRequested() {
        if let i = args.firstIndex(of: "-SlapssDemoAppearance"), args.indices.contains(i + 1) {
            NSApp.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
        }
        if isDataActive { logPopoverWindow() }
        let overlay = flag("-SlapssDemoOverlay")
        if overlay.present {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showOverlay(startingIn: overlay.value ?? 70)
            }
        }
    }

    // MARK: - Demo day

    /// Frozen at first use, so every refresh publishes identical data and the
    /// agenda doesn't shift under a screenshot.
    static let meetings: [MeetingEvent] = {
        let now = Date()
        let heroStart = now.addingTimeInterval(flag("-SlapssDemoData").value ?? 240)
        let work = MeetingEvent.ColorRGBA(red: 0.24, green: 0.52, blue: 0.93, alpha: 1)
        let personal = MeetingEvent.ColorRGBA(red: 0.30, green: 0.69, blue: 0.40, alpha: 1)
        let team = ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Linus Torvalds", "Margaret Hamilton"]

        func event(_ title: String, _ start: Date, minutes: Double, location: String? = nil,
                   link: String = "", color: MeetingEvent.ColorRGBA = work,
                   calendar: String = "Work", attendees: [String] = []) -> MeetingEvent {
            MeetingEvent(
                id: "demo:\(title)", title: title, startDate: start,
                endDate: start.addingTimeInterval(minutes * 60), location: location,
                rawDetails: link, calendarTitle: calendar, calendarColor: color,
                source: .eventKit, attendees: attendees
            )
        }

        return [
            event("Daily stand-up", now.addingTimeInterval(-3 * 3600), minutes: 15,
                  link: "https://teams.microsoft.com/l/meetup-join/demo", attendees: Array(team.prefix(4))),
            event("Roadmap sync", now.addingTimeInterval(-90 * 60), minutes: 30,
                  location: "Room 2A", attendees: Array(team.prefix(3))),
            event("Design review", heroStart, minutes: 1, location: "Room 4B",
                  link: "https://meet.google.com/abc-defg-hij", attendees: team),
            event("Sprint planning", heroStart.addingTimeInterval(3600), minutes: 45,
                  link: "https://teams.microsoft.com/l/meetup-join/demo", attendees: team),
            MeetingEvent(
                id: "reminder:demo", title: "Send the Q3 report",
                startDate: heroStart.addingTimeInterval(2 * 3600),
                endDate: heroStart.addingTimeInterval(2 * 3600), location: nil,
                rawDetails: "", calendarTitle: "Reminders", calendarColor: personal,
                source: .eventKit, attendees: [], kind: .reminder
            ),
            event("Customer call", heroStart.addingTimeInterval(3 * 3600), minutes: 30,
                  link: "https://us02web.zoom.us/j/1234567890", attendees: ["Ada Lovelace", "Alan Turing"]),
            event("Gym", heroStart.addingTimeInterval(5 * 3600), minutes: 60,
                  color: personal, calendar: "Personal"),
        ].sorted { $0.startDate < $1.startDate }
    }()

    // MARK: - Popover

    /// Prints the popover's window id each time it opens, for
    /// `screencapture -o -l <id>` (just the popover, with no desktop).
    ///
    /// The popover can't be opened from inside the app. The MenuBarExtra's
    /// NSStatusBarButton has no target/action, and SwiftUI ignored every
    /// in-process click tried: `performClick`, an NSEvent sent or posted,
    /// and a CGEvent posted to our own pid. It opens only on a real click.
    /// Also note the app owns several NSStatusBarWindows, all but one
    /// parked off-screen at y = -33.
    private static func logPopoverWindow() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow,
                      MenuBarContentView.menuBarExtraWindows().contains(window) else { return }
                print("SLAPSS_POPOVER_WINDOW \(window.windowNumber)")
                fflush(stdout)
            }
        }
    }

    // MARK: - Overlay

    private static let overlayController = OverlayWindowController()

    private static func showOverlay(startingIn offset: TimeInterval) {
        let start = Date().addingTimeInterval(offset)
        let meeting = MeetingEvent(
            id: "demo-overlay", title: "Design review", startDate: start,
            endDate: start.addingTimeInterval(30 * 60), location: "Room 4B",
            rawDetails: "https://meet.google.com/abc-defg-hij", calendarTitle: "Work",
            calendarColor: nil, source: .eventKit,
            attendees: ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Linus Torvalds", "Margaret Hamilton"]
        )
        let hide = { overlayController.hide() }
        overlayController.show(
            meeting: meeting,
            onJoin: hide,
            onComplete: nil,
            onDismiss: hide,
            onSnoozeMinutes: { _ in hide() },
            onSnoozeUntilEnd: hide,
            mirrorOnAllScreens: false,
            lm: LocalizationManager(),
            theme: AppTheme(rawValue: UserDefaults.standard.string(forKey: "slapss.theme") ?? "") ?? .sunset
        )
    }
}
#endif
