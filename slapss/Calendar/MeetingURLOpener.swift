//
//  MeetingURLOpener.swift
//  slapss
//
//  Single entry point for opening a meeting join URL. Centralized so both
//  the alert overlay's "Join" button and the menu bar popover go through
//  the same native-app-preferring path.
//
//  Behavior:
//   - Microsoft Teams URLs are rewritten to `msteams://` so the desktop app
//     handles them directly. Falls back to https if Teams.app isn't installed.
//   - Zoom / Google Meet / Webex / others: their https join pages already
//     redirect to the native app on launch via their own custom URL schemes,
//     so opening the original URL is sufficient.
//

import AppKit
import Foundation

@MainActor
enum MeetingURLOpener {
    /// - Parameter authUser: the Google `authuser` index for this meeting's
    ///   calendar, if the user configured one. When set and the URL is a
    ///   `meet.google.com` link, `?authuser=N` is applied so the meeting opens
    ///   in the matching Google account. Ignored for non-Meet URLs.
    static func open(_ url: URL, authUser: Int? = nil) {
        let target = applyAuthUserIfNeeded(url, authUser: authUser)
        let urlString = target.absoluteString

        if urlString.contains("teams.microsoft.com") || urlString.contains("teams.live.com") {
            let deepLinkString = urlString.replacingOccurrences(of: "https://", with: "msteams://")
            if let deepLink = URL(string: deepLinkString),
               NSWorkspace.shared.urlForApplication(toOpen: deepLink) != nil {
                NSWorkspace.shared.open(deepLink)
                return
            }
        }

        NSWorkspace.shared.open(target)
    }

    /// Opens a calendar event directly in Calendar.app.
    ///
    /// ⚠️ Uses `ical://ekevent/<identifier>` — an **undocumented** URL scheme
    /// (not part of any public Apple API). It's widely reported to work
    /// across recent macOS versions, but Apple could change or drop it in a
    /// future release without notice. If "Open in Calendar" silently stops
    /// working after an OS update, this is the first place to check.
    static func openInCalendar(eventIdentifier: String) {
        guard let url = URL(string: "ical://ekevent/\(eventIdentifier)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Appends (or replaces) the `authuser` query parameter on Google Meet
    /// links. Leaves every other URL untouched. Replacing rather than blindly
    /// appending guards against a meeting link that already carries an
    /// `authuser` value.
    private static func applyAuthUserIfNeeded(_ url: URL, authUser: Int?) -> URL {
        guard let authUser,
              let host = url.host, host.contains("meet.google.com"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }

        var items = (components.queryItems ?? []).filter { $0.name != "authuser" }
        items.append(URLQueryItem(name: "authuser", value: String(authUser)))
        components.queryItems = items
        return components.url ?? url
    }
}
