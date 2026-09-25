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

    /// Static assets a provider's own domain serves inside HTML invitations.
    /// Zoom's Outlook add-in embeds `https://<sub>.zoom.us/static/.../ZoomLogo_110_25.png`
    /// *above* the join link, so a first-match scan opened the logo instead of
    /// the meeting (user report, September 2026).
    private static let assetExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "css", "js"]

    /// Returns the first recognized meeting URL in the input, or nil.
    /// `@MainActor` because NSRegularExpression methods are MainActor-isolated
    /// in the Xcode 26 SDK; all callers are already on the main actor.
    @MainActor
    static func firstURL(in text: String) -> URL? {
        let text = unwrapClickProtection(in: text)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (_, regex) in patterns {
            for match in regex.matches(in: text, options: [], range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let raw = String(text[swiftRange])
                // Strip trailing punctuation that often gets glued to URLs
                // when parsing email-style descriptions.
                let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))
                guard let url = URL(string: cleaned),
                      !assetExtensions.contains(url.pathExtension.lowercased()) else { continue }
                return url
            }
        }
        return nil
    }

    // MARK: - Click-protection wrappers

    /// Corporate mail gateways rewrite every link in an invitation to go
    /// through their scanner first. The real join URL is still inside, but
    /// encoded, so the provider patterns above either miss it (SafeLinks,
    /// Proofpoint v2: percent/dash-encoded) or match it with the wrapper's
    /// tail glued on (Proofpoint v3: `…/j/123__;!!abc$`). Each wrapper is
    /// decoded locally, no network, and swapped for its inner URL in the text.
    /// The provider patterns still decide what counts as a join link, so an
    /// unwrapped non-meeting URL changes nothing. A wrapper that fails to
    /// decode stays as it was, which is the behaviour before this existed.
    /// Opaque-token wrappers (Mimecast, Cisco) can't be decoded offline and
    /// are left alone on purpose.
    private static let wrapperPattern = try! NSRegularExpression(
        pattern: #"https?://(?:[a-z0-9-]+\.safelinks\.protection\.(?:outlook\.com|office365\.us|outlook\.de)|urldefense(?:\.proofpoint)?\.com|linkprotect\.cudasvc\.com)/[^\s<>"]+"#,
        options: [.caseInsensitive]
    )

    static func unwrapClickProtection(in text: String) -> String {
        var result = text
        // Two passes cover one wrapper nested in another (SafeLinks around
        // Proofpoint happens when mail crosses two tenants).
        for _ in 0..<2 {
            let ns = result as NSString
            let matches = wrapperPattern.matches(in: result, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { break }
            var out = result
            for match in matches.reversed() {
                let wrapped = ns.substring(with: match.range)
                guard let inner = decodeWrapper(wrapped),
                      let range = Range(match.range, in: out) else { continue }
                out.replaceSubrange(range, with: inner)
            }
            if out == result { break }
            result = out
        }
        return result
    }

    /// The inner URL of one wrapper link, or nil if it doesn't decode to an
    /// http(s) URL.
    static func decodeWrapper(_ wrapped: String) -> String? {
        // HTML invitation bodies escape the query separator.
        let link = wrapped.replacingOccurrences(of: "&amp;", with: "&")
        let decoded: String?
        if let r = link.range(of: "/v3/__") {
            decoded = decodeProofpointV3(String(link[r.upperBound...]))
        } else if let c = URLComponents(string: link) {
            let items = c.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }
            if c.path.hasPrefix("/v2/url"), let u = value("u") {
                // v2: "-" stands for "%" and "_" for "/", then percent-decode.
                decoded = u.replacingOccurrences(of: "-", with: "%")
                    .replacingOccurrences(of: "_", with: "/")
                    .removingPercentEncoding
            } else {
                // SafeLinks ?url=, Proofpoint v1 ?u=, Barracuda ?a=.
                // queryItems are already percent-decoded.
                decoded = value("url") ?? value("u") ?? value("a")
            }
        } else {
            decoded = nil
        }
        guard var decoded, decoded.lowercased().hasPrefix("http") else { return nil }
        // Some gateways collapse "https://" to "https:/"; the reference
        // decoder repairs it the same way.
        if let r = decoded.range(of: #"^https?:/(?!/)"#, options: [.regularExpression, .caseInsensitive]) {
            decoded.insert("/", at: r.upperBound)
        }
        return decoded
    }

    /// Proofpoint v3: `<url>__;<base64>!!<signature>`. Characters Proofpoint
    /// considers unsafe are replaced in `<url>` by `*`, and their originals
    /// travel in `<base64>` in order. `**X` is a run: the next N originals,
    /// N from X's position in the run alphabet, plus 2. Same algorithm as
    /// Proofpoint's published reference decoder.
    private static func decodeProofpointV3(_ rest: String) -> String? {
        guard let end = rest.range(of: "__;") else { return nil }
        let url = rest[..<end.lowerBound]
        let tail = rest[end.upperBound...]
        var b64 = String(tail.prefix { $0 != "!" })
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let originals = String(data: data, encoding: .utf8) else { return nil }
        var pool = originals.makeIterator()
        let runAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var out = ""
        let chars = Array(url)
        var i = 0
        while i < chars.count {
            if chars[i] != "*" { out.append(chars[i]); i += 1; continue }
            if i + 2 < chars.count, chars[i + 1] == "*", let n = runAlphabet.firstIndex(of: chars[i + 2]) {
                for _ in 0..<(n + 2) {
                    guard let c = pool.next() else { return nil }
                    out.append(c)
                }
                i += 3
            } else {
                guard let c = pool.next() else { return nil }
                out.append(c)
                i += 1
            }
        }
        return out
    }
}
