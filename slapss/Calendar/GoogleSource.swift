import Combine
import Foundation

@MainActor
final class GoogleSource: ObservableObject {
    enum SignInState: Equatable {
        case signedOut
        case signingIn
        case signedIn(displayName: String?)
        case error(String)
    }

    @Published private(set) var state: SignInState = .signedOut
    @Published private(set) var availableCalendars: [GoogleTypes.CalendarListEntry] = []

    var enabledCalendarIDs: Set<String> = []
    var onChange: (() -> Void)?

    private let client: GoogleOAuthClient
    private let urlSession: URLSession
    private var pollTimer: Timer?
    private var lastFetchedEvents: [MeetingEvent] = []

    init() {
        self.client = GoogleOAuthClient()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)

        if client.isConfigured && client.isSignedIn {
            Task { await self.completeSignIn() }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    var isConfigured: Bool { client.isConfigured }
    var signedInEmail: String? { client.account?.email }

    func signIn() async {
        guard client.isConfigured else {
            state = .error("Google sign-in isn't configured.")
            return
        }
        state = .signingIn
        do {
            try await client.signIn()
            await completeSignIn()
        } catch {
            let typed = GoogleOAuthClient.classify(error)
            state = .error(typed.localizedDescription)
        }
    }

    func signOut() async {
        await client.signOut()
        state = .signedOut
        availableCalendars = []
        lastFetchedEvents = []
        pollTimer?.invalidate()
        pollTimer = nil
        onChange?()
    }

    func completeSignIn() async {
        state = .signedIn(displayName: client.account?.email)
        await refreshCalendarList()
        startPollTimer()
        onChange?()
    }

    func refreshCalendarList() async {
        let token: String
        do {
            token = try await client.acquireTokenSilently()
        } catch let error as GoogleOAuthClient.SignInError {
            switch error {
            case .noRefreshToken, .refreshTokenRevoked:
                state = .error(error.localizedDescription)
                lastFetchedEvents = []
            default:
                state = .error("Couldn't load calendars: \(error.localizedDescription)")
            }
            return
        } catch {
            state = .error("Couldn't load calendars: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else { return }

        do {
            var req = authedRequest(url: url, token: token)
            var (data, response) = try await urlSession.data(for: req)
            var http = response as? HTTPURLResponse

            if http?.statusCode == 401 {
                let refreshedToken = try await client.acquireTokenSilently(forceRefresh: true)
                req = authedRequest(url: url, token: refreshedToken)
                (data, response) = try await urlSession.data(for: req)
                http = response as? HTTPURLResponse
            }

            guard let http else {
                state = .error("Couldn't load calendars: bad server response.")
                return
            }
            if http.statusCode == 401 {
                state = .error("Google session expired. Please sign in again.")
                lastFetchedEvents = []
                return
            }
            guard http.statusCode == 200 else {
                state = .error("Couldn't load calendars (HTTP \(http.statusCode)).")
                return
            }

            let decoded = try JSONDecoder().decode(GoogleTypes.CalendarListResponse.self, from: data)
            availableCalendars = (decoded.items ?? []).sorted { lhs, rhs in
                let lhsPrimary = lhs.primary == true
                let rhsPrimary = rhs.primary == true
                if lhsPrimary != rhsPrimary { return lhsPrimary }
                let lhsName = lhs.summaryOverride ?? lhs.summary ?? lhs.id
                let rhsName = rhs.summaryOverride ?? rhs.summary ?? rhs.id
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            if case .error = state {
                state = .signedIn(displayName: client.account?.email)
            }
        } catch let error as GoogleOAuthClient.SignInError {
            switch error {
            case .noRefreshToken, .refreshTokenRevoked:
                state = .error(error.localizedDescription)
                lastFetchedEvents = []
            default:
                state = .error("Couldn't load calendars: \(error.localizedDescription)")
            }
        } catch {
            state = .error("Couldn't load calendars: \(error.localizedDescription)")
        }
    }

    func fetchTodayAndAhead(horizon: TimeInterval = 24 * 3600) async -> [MeetingEvent] {
        guard case .signedIn = state else { return [] }

        let calendars = enabledCalendars()
        guard !calendars.isEmpty else {
            lastFetchedEvents = []
            return []
        }

        var token: String
        do {
            token = try await client.acquireTokenSilently()
        } catch let error as GoogleOAuthClient.SignInError {
            switch error {
            case .noRefreshToken, .refreshTokenRevoked:
                state = .error(error.localizedDescription)
                lastFetchedEvents = []
                return []
            default:
                return lastFetchedEvents
            }
        } catch {
            return lastFetchedEvents
        }

        let now = Date()
        let end = now.addingTimeInterval(horizon)
        let queryStart = Calendar.current.startOfDay(for: now)
        let startStr = Self.iso8601UTC.string(from: queryStart)
        let endStr = Self.iso8601UTC.string(from: end)

        var all: [MeetingEvent] = []
        var didForceRefresh = false

        for cal in calendars {
            guard let url = eventsURL(calendarID: cal.id, timeMin: startStr, timeMax: endStr) else {
                continue
            }
            do {
                var req = authedRequest(url: url, token: token)
                var (data, response) = try await urlSession.data(for: req)
                var http = response as? HTTPURLResponse

                if http?.statusCode == 401 && !didForceRefresh {
                    didForceRefresh = true
                    token = try await client.acquireTokenSilently(forceRefresh: true)
                    req = authedRequest(url: url, token: token)
                    (data, response) = try await urlSession.data(for: req)
                    http = response as? HTTPURLResponse
                }

                if http?.statusCode == 401 {
                    state = .error("Google access expired or was revoked. Please sign in again.")
                    lastFetchedEvents = []
                    return []
                }

                guard let http, http.statusCode == 200 else {
                    all.append(contentsOf: lastFetchedEvents.filter { $0.calendarID == cal.id })
                    continue
                }

                let decoded = try JSONDecoder().decode(GoogleTypes.EventListResponse.self, from: data)
                let events = (decoded.items ?? [])
                    .filter { $0.status != "cancelled" && $0.start?.dateTime != nil && $0.end?.dateTime != nil }
                    .compactMap { toMeetingEvent($0, calendar: cal) }
                all.append(contentsOf: events)
            } catch let error as GoogleOAuthClient.SignInError {
                switch error {
                case .noRefreshToken, .refreshTokenRevoked:
                    state = .error(error.localizedDescription)
                    lastFetchedEvents = []
                    return []
                default:
                    all.append(contentsOf: lastFetchedEvents.filter { $0.calendarID == cal.id })
                }
            } catch {
                all.append(contentsOf: lastFetchedEvents.filter { $0.calendarID == cal.id })
            }
        }

        let sorted = all.sorted { $0.startDate < $1.startDate }
        lastFetchedEvents = sorted
        return sorted
    }

    private func enabledCalendars() -> [GoogleTypes.CalendarListEntry] {
        enabledCalendarIDs.isEmpty
            ? availableCalendars
            : availableCalendars.filter { enabledCalendarIDs.contains($0.id) }
    }

    private func eventsURL(calendarID: String, timeMin: String, timeMax: String) -> URL? {
        // Google calendar IDs often include #, +, / or @ and must encode as a single path segment.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/calendar/v3/calendars/\(encodedID)/events"
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        return components.url
    }

    private func authedRequest(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func toMeetingEvent(_ event: GoogleTypes.Event, calendar: GoogleTypes.CalendarListEntry) -> MeetingEvent? {
        guard let startRaw = event.start?.dateTime,
              let endRaw = event.end?.dateTime,
              let start = Self.parseGoogleDate(startRaw),
              let end = Self.parseGoogleDate(endRaw) else {
            return nil
        }

        var details: [String] = []
        if let hangout = event.hangoutLink, !hangout.isEmpty {
            details.append(hangout)
        }
        if let entryPoints = event.conferenceData?.entryPoints {
            for entryPoint in entryPoints where entryPoint.entryPointType == "video" {
                if let uri = entryPoint.uri, !uri.isEmpty {
                    details.append(uri)
                }
            }
        }
        if let description = event.description, !description.isEmpty {
            details.append(description)
        }
        if let location = event.location, !location.isEmpty {
            details.append(location)
        }

        let attendees: [String] = (event.attendees ?? []).compactMap { attendee in
            if let name = attendee.displayName, !name.isEmpty { return name }
            if let email = attendee.email, !email.isEmpty { return email }
            return nil
        }

        let selfAttendee = event.attendees?.first(where: { $0.isSelf == true })

        return MeetingEvent(
            id: "google:\(calendar.id):\(event.id)",
            title: event.summary ?? "(Untitled)",
            startDate: start,
            endDate: end,
            location: event.location,
            rawDetails: details.joined(separator: "\n"),
            calendarTitle: calendar.summaryOverride ?? calendar.summary ?? calendar.id,
            calendarColor: parseHex(calendar.backgroundColor),
            calendarID: calendar.id,
            source: .google,
            attendees: attendees,
            rsvp: Self.rsvp(from: selfAttendee?.responseStatus),
            iCalUID: event.iCalUID,
            calendarWebURL: event.htmlLink.flatMap(URL.init(string:)),
            googleAuthUserEmail: client.account?.email
        )
    }

    private static func rsvp(from response: String?) -> MeetingEvent.RSVP {
        switch response {
        case "accepted":    return .accepted
        case "tentative":   return .tentative
        case "declined":    return .declined
        case "needsAction": return .needsAction
        default:            return .unknown
        }
    }

    private static func parseGoogleDate(_ raw: String) -> Date? {
        rfc3339Fractional.date(from: raw) ?? rfc3339.date(from: raw)
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

    // NOT Timer.scheduledTimer: .default runloop mode stalls while menus/popovers
    // track and is App Nap-vulnerable in a menu bar app.
    private func startPollTimer() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let iso8601UTC: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let rfc3339Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
