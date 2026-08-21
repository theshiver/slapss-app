//
//  GraphSource.swift
//  slapss
//
//  Calendar source backed by Microsoft Graph. Mirrors EventKitSource's shape
//  so the aggregator can treat them interchangeably.
//
//  Polling strategy: fetch every 5 minutes via a Timer. Graph supports webhook
//  subscriptions for real-time updates but those require a public HTTPS
//  endpoint, which a sandboxed local app can't expose. 5-min staleness is
//  acceptable for v1.
//
//  Threading: @MainActor — all state mutations and user-facing properties live
//  on the main actor. Network I/O happens via async/await which hops off and
//  back on its own.
//

import Combine
import Foundation

@MainActor
final class GraphSource: ObservableObject {
    enum SignInState: Equatable {
        case signedOut
        case signingIn
        case signedIn(displayName: String?)
        case error(String)
    }

    @Published private(set) var state: SignInState = .signedOut
    @Published private(set) var availableCalendars: [GraphTypes.Calendar] = []

    /// Set of Graph calendar IDs the user opted into. Empty = all.
    var enabledCalendarIDs: Set<String> = []

    /// Called when the underlying source has new data — aggregator subscribes.
    var onChange: (() -> Void)?

    private let msal: MSALClient
    private let urlSession: URLSession
    private var pollTimer: Timer?

    private static let graphBase: URL = {
        guard let url = URL(string: "https://graph.microsoft.com/v1.0") else {
            fatalError("GraphSource: graphBase URL is malformed — compile-time programming error")
        }
        return url
    }()

    init() {
        self.msal = MSALClient()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)

        // If MSAL already has a cached account from a previous session, restore.
        if msal.isConfigured && msal.isSignedIn {
            Task { await self.completeSignIn() }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    var isConfigured: Bool { msal.isConfigured }

    // MARK: - Sign-in lifecycle

    func signIn() async {
        guard msal.isConfigured else {
            state = .error("Microsoft sign-in isn't configured. See AZURE_SETUP.md.")
            return
        }
        state = .signingIn
        do {
            try await msal.signIn()
            await completeSignIn()
        } catch {
            let typed = MSALClient.classify(error)
            state = .error(typed.localizedDescription)
        }
    }

    func signOut() async {
        try? await msal.signOut()
        state = .signedOut
        availableCalendars = []
        pollTimer?.invalidate()
        pollTimer = nil
        onChange?()
    }

    private func completeSignIn() async {
        state = .signedIn(displayName: msal.account?.username)
        await refreshCalendarList()
        startPollTimer()
        onChange?()
    }

    // MARK: - Public fetch surface (called by aggregator)

    /// Returns events from start-of-today to `now + horizon` across all
    /// enabled calendars. Includes already-finished meetings from earlier
    /// today; the aggregator splits past vs upcoming. Empty on sign-out or error.
    func fetchTodayAndAhead(horizon: TimeInterval = 24 * 3600) async -> [MeetingEvent] {
        guard case .signedIn = state else { return [] }

        let calendars = enabledCalendars()
        guard !calendars.isEmpty else { return [] }

        guard let token = try? await msal.acquireTokenSilently() else { return [] }

        let now = Date()
        let end = now.addingTimeInterval(horizon)
        // Graph's calendarView only returns events whose START is inside the
        // [startDateTime, endDateTime] window. Anchor the lower bound at
        // start-of-today so we capture both still-running sessions AND any
        // already-finished morning meetings the popover wants to show.
        let queryStart = Calendar.current.startOfDay(for: now)
        let startStr = Self.iso8601UTC.string(from: queryStart)
        let endStr = Self.iso8601UTC.string(from: end)

        var all: [MeetingEvent] = []
        for cal in calendars {
            guard let url = calendarViewURL(calendarID: cal.id, start: startStr, end: endStr) else { continue }
            let req = authedRequest(url: url, token: token)
            do {
                let (data, _) = try await urlSession.data(for: req)
                let response = try JSONDecoder().decode(GraphTypes.EventListResponse.self, from: data)
                all.append(contentsOf: response.value
                    .filter { $0.isCancelled != true && $0.isAllDay != true }
                    .compactMap { event in toMeetingEvent(event, calendar: cal) }
                )
            } catch {
                // Skip this calendar on error — don't fail the whole sync.
                continue
            }
        }
        return all.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Internals

    private func refreshCalendarList() async {
        guard let token = try? await msal.acquireTokenSilently() else { return }
        let url = Self.graphBase.appendingPathComponent("me/calendars")
        let req = authedRequest(url: url, token: token)
        do {
            let (data, _) = try await urlSession.data(for: req)
            let response = try JSONDecoder().decode(GraphTypes.CalendarListResponse.self, from: data)
            availableCalendars = response.value
        } catch {
            // Surface but don't blow up the sign-in flow.
            state = .error("Couldn't load calendars: \(error.localizedDescription)")
        }
    }

    private func enabledCalendars() -> [GraphTypes.Calendar] {
        enabledCalendarIDs.isEmpty
            ? availableCalendars
            : availableCalendars.filter { enabledCalendarIDs.contains($0.id) }
    }

    private func calendarViewURL(calendarID: String, start: String, end: String) -> URL? {
        var components = URLComponents(url: Self.graphBase.appendingPathComponent("me/calendars/\(calendarID)/calendarView"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "startDateTime", value: start),
            URLQueryItem(name: "endDateTime", value: end),
            URLQueryItem(name: "$top", value: "100"),
            URLQueryItem(name: "$select", value: "id,subject,start,end,location,bodyPreview,onlineMeeting,webLink,isAllDay,isCancelled,attendees,responseStatus"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
        ]
        return components?.url
    }

    private func authedRequest(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Force UTC for all dateTime fields — simplifies our decode path.
        req.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        return req
    }

    private func toMeetingEvent(_ event: GraphTypes.Event, calendar: GraphTypes.Calendar) -> MeetingEvent? {
        guard let start = parseGraphDate(event.start.dateTime),
              let end = parseGraphDate(event.end.dateTime) else {
            return nil
        }

        var details: [String] = []
        if let preview = event.bodyPreview, !preview.isEmpty { details.append(preview) }
        if let join = event.onlineMeeting?.joinUrl, !join.isEmpty { details.append(join) }
        if let web = event.webLink, !web.isEmpty { details.append(web) }
        if let loc = event.location?.displayName, !loc.isEmpty { details.append(loc) }

        let attendees: [String] = (event.attendees ?? []).compactMap { attendee in
            if let name = attendee.emailAddress.name, !name.isEmpty { return name }
            return attendee.emailAddress.address
        }

        return MeetingEvent(
            id: "graph:\(event.id)",
            title: event.subject ?? "(Untitled)",
            startDate: start,
            endDate: end,
            location: event.location?.displayName,
            rawDetails: details.joined(separator: "\n"),
            calendarTitle: calendar.name,
            calendarColor: parseHex(calendar.hexColor),
            source: .graph,
            attendees: attendees,
            rsvp: Self.rsvp(from: event.responseStatus?.response)
        )
    }

    /// Maps a Graph `responseStatus.response` string onto our RSVP enum.
    /// Organizer and unknown/missing values map to `.unknown` (always fires).
    private static func rsvp(from response: String?) -> MeetingEvent.RSVP {
        switch response {
        case "accepted":           return .accepted
        case "tentativelyAccepted": return .tentative
        case "declined":           return .declined
        case "notResponded":       return .needsAction
        default:                   return .unknown // none / organizer / nil
        }
    }

    private func parseGraphDate(_ raw: String) -> Date? {
        // Graph returns "2026-04-30T13:00:00.0000000" (no Z) when Prefer header
        // forces UTC. ISO8601DateFormatter doesn't accept 7-digit fractional
        // seconds, so we use a DateFormatter with explicit format.
        let trimmed = String(raw.prefix(19)) // "yyyy-MM-ddTHH:mm:ss"
        return Self.fixedFormatter.date(from: trimmed)
    }

    private func parseHex(_ hex: String?) -> MeetingEvent.ColorRGBA? {
        guard var hex = hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return MeetingEvent.ColorRGBA(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1.0
        )
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    // MARK: - Static formatters

    /// "2026-04-30T13:00:00Z" — what Graph expects for query params.
    private static let iso8601UTC: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Parses Graph's "2026-04-30T13:00:00" (no fractional, no zone, in UTC because
    /// of the Prefer header).
    private static let fixedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}
