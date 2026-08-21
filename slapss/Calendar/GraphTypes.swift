//
//  GraphTypes.swift
//  slapss
//
//  Codable DTOs for the slice of Microsoft Graph we actually use:
//   - GET /me/calendars
//   - GET /me/calendars/{id}/calendarView?startDateTime=...&endDateTime=...
//   - GET /me
//
//  Only fields we render are decoded. Future-proof: Graph adds fields all the
//  time, and our decoders simply ignore unknowns.
//

import Foundation

enum GraphTypes {
    // MARK: - Calendars

    struct CalendarListResponse: Decodable {
        let value: [Calendar]
    }

    struct Calendar: Decodable, Identifiable {
        let id: String
        let name: String
        /// Hex like "#FF0000" — sometimes nil on Graph responses.
        let hexColor: String?
        let isDefaultCalendar: Bool?
    }

    // MARK: - Events

    struct EventListResponse: Decodable {
        let value: [Event]
    }

    struct Event: Decodable {
        let id: String
        let subject: String?
        let start: DateTimeTimeZone
        let end: DateTimeTimeZone
        let location: Location?
        let bodyPreview: String?
        let onlineMeeting: OnlineMeeting?
        let webLink: String?
        let isAllDay: Bool?
        let isCancelled: Bool?
        let attendees: [Attendee]?
        let responseStatus: ResponseStatus?
    }

    /// The signed-in user's response to the event. `response` is one of
    /// none / organizer / tentativelyAccepted / accepted / declined / notResponded.
    struct ResponseStatus: Decodable {
        let response: String?
    }

    struct Attendee: Decodable {
        struct EmailAddress: Decodable {
            let name: String?
            let address: String?
        }
        let emailAddress: EmailAddress
    }

    struct DateTimeTimeZone: Decodable {
        /// Format: "2026-04-30T13:00:00.0000000" — no timezone suffix.
        /// We force UTC via the `Prefer: outlook.timezone="UTC"` request header,
        /// so all dateTime values are in UTC and the parser appends 'Z'.
        let dateTime: String
        let timeZone: String
    }

    struct Location: Decodable {
        let displayName: String?
    }

    struct OnlineMeeting: Decodable {
        let joinUrl: String?
    }

    // MARK: - Profile

    struct UserResponse: Decodable {
        let id: String
        let displayName: String?
        let userPrincipalName: String?
        let mail: String?
    }
}
