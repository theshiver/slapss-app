import Foundation

enum GoogleOAuthConfig {
    static let clientID = "924616979013-8o4hcrb87ls5f3gbrr0evdclu65rik86.apps.googleusercontent.com"
    static let reversedClientID = "com.googleusercontent.apps.924616979013-8o4hcrb87ls5f3gbrr0evdclu65rik86"
    static let redirectURI = "\(reversedClientID):/oauth2redirect"
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "openid",
        "email",
    ]

    static var isPlaceholder: Bool {
        clientID == "REPLACE_WITH_YOUR_CLIENT_ID"
    }
}
