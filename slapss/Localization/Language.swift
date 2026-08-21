//
//  Language.swift
//  slapss
//
//  Supported UI languages. English is the default / fallback.
//

import Foundation

enum Language: String, CaseIterable, Identifiable {
    case english  = "en"
    case turkish  = "tr"
    case spanish  = "es"
    case german   = "de"
    case italian  = "it"
    case french   = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .spanish: return "Español"
        case .german:  return "Deutsch"
        case .italian: return "Italiano"
        case .french:  return "Français"
        }
    }

    /// Attempt to map the device's first preferred language to one of the
    /// supported languages. Returns nil when none match — the caller should
    /// fall back to .english.
    static func matchingSystemLanguage() -> Language? {
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? ""
            if let match = Language(rawValue: code) {
                return match
            }
        }
        return nil
    }
}
