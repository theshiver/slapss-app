import Foundation

enum GoogleTypes {
    struct CalendarListResponse: Decodable {
        let items: [CalendarListEntry]?
    }

    struct CalendarListEntry: Decodable, Identifiable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let primary: Bool?
        let selected: Bool?
        let accessRole: String?
    }

    struct EventListResponse: Decodable {
        let items: [Event]?
    }

    struct Event: Decodable {
        let id: String
        let iCalUID: String?
        let status: String?
        let summary: String?
        let description: String?
        let location: String?
        let htmlLink: String?
        let hangoutLink: String?
        let conferenceData: ConferenceData?
        let start: EventDateTime?
        let end: EventDateTime?
        let attendees: [Attendee]?
    }

    struct EventDateTime: Decodable {
        let dateTime: String?
        let date: String?
        let timeZone: String?
    }

    struct ConferenceData: Decodable {
        let entryPoints: [EntryPoint]?
    }

    struct EntryPoint: Decodable {
        let entryPointType: String?
        let uri: String?
    }

    struct Attendee: Decodable {
        let email: String?
        let displayName: String?
        let responseStatus: String?
        let isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case email
            case displayName
            case responseStatus
            case isSelf = "self"
        }
    }
}
