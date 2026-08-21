//
//  MeetingLinkDetector.swift
//  slapss
//
//  Finds the join URL inside an event's body/location text. Prioritized so a
//  Zoom link wins over a generic URL also embedded in the event description.
//

import Foundation

enum MeetingLinkDetector {
    /// Ordered patterns. First match wins. Each pattern matches the full URL
    /// including its host so we extract the original link rather than reconstructing.
    private static let patterns: [(name: String, regex: NSRegularExpression)] = {
        let raws: [(String, String)] = [
            ("Zoom",  #"https?://[a-zA-Z0-9.-]*zoom\.us/[^\s<>"]+"#),
            ("Teams", #"https?://teams\.microsoft\.com/[^\s<>"]+"#),
            ("Teams Live", #"https?://teams\.live\.com/[^\s<>"]+"#),
            ("Meet",  #"https?://meet\.google\.com/[^\s<>"]+"#),
            ("Webex", #"https?://[a-zA-Z0-9.-]*webex\.com/[^\s<>"]+"#),
            ("Whereby", #"https?://[a-zA-Z0-9.-]*whereby\.com/[^\s<>"]+"#),
            ("Around", #"https?://meet\.around\.co/[^\s<>"]+"#),
        ]
        return raws.compactMap { name, raw in
            guard let regex = try? NSRegularExpression(pattern: raw, options: [.caseInsensitive]) else {
                return nil
            }
            return (name, regex)
        }
    }()

    /// Returns the first recognized meeting URL in the input, or nil.
    /// `@MainActor` because NSRegularExpression methods are MainActor-isolated
    /// in the Xcode 26 SDK; all callers are already on the main actor.
    @MainActor
    static func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (_, regex) in patterns {
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let swiftRange = Range(match.range, in: text) {
                let raw = String(text[swiftRange])
                // Strip trailing punctuation that often gets glued to URLs
                // when parsing email-style descriptions.
                let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))
                if let url = URL(string: cleaned) {
                    return url
                }
            }
        }
        return nil
    }
}
