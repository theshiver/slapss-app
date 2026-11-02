//
//  ReviewPrompt.swift
//  slapss
//
//  Decides when to ask for an App Store rating. Apple shows its own prompt
//  at most three times a year and may decide to show nothing; this only keeps
//  us from asking before Slapss has proved itself. Both values stay in
//  UserDefaults on the Mac and are never sent anywhere.
//

import Foundation

enum ReviewPrompt {
    private static let joinCountKey = "slapss.joinCount"
    private static let askedVersionKey = "slapss.reviewRequestedVersion"
    private static let joinsBeforeAsking = 5

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Called when Join actually opened a meeting link.
    static func recordJoin(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: joinCountKey) + 1, forKey: joinCountKey)
    }

    /// Enough joins, and not yet asked in this app version.
    static func isDue(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: joinCountKey) >= joinsBeforeAsking
            && defaults.string(forKey: askedVersionKey) != appVersion
    }

    static func markAsked(defaults: UserDefaults = .standard) {
        defaults.set(appVersion, forKey: askedVersionKey)
    }
}
