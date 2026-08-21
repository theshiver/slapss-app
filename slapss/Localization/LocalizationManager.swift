//
//  LocalizationManager.swift
//  slapss
//
//  Runtime localization manager. Holds the active Language, resolves string
//  keys against the correct translation table, and publishes changes so
//  SwiftUI views re-render whenever the user switches language in Settings.
//
//  Usage in any view:
//
//    @EnvironmentObject private var lm: LocalizationManager
//
//    // Static string
//    Text(lm["settings.tab.general"])
//
//    // Format string with one integer argument
//    lm.t("alert.status.inMinutes", absMin)
//
//    // Format string with one string argument
//    lm.t("settings.microsoft.signedInAs", displayName)
//

import Combine
import Foundation

@MainActor
final class LocalizationManager: ObservableObject {

    // MARK: - Persistence key

    private enum Key {
        static let appLanguage = "slapss.appLanguage"
        // `nil` stored here means "never been set" — used for first-launch
        // OS language detection.
        static let languageSetByUser = "slapss.languageSetByUser"
    }

    // MARK: - Published state

    @Published private(set) var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Key.appLanguage)
        }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        if let stored = defaults.string(forKey: Key.appLanguage),
           let lang = Language(rawValue: stored) {
            // User has previously chosen a language (or the OS-default was
            // saved on first launch) — respect it.
            self.language = lang
        } else {
            // First launch: try to match the device's preferred language.
            let detected = Language.matchingSystemLanguage() ?? .english
            self.language = detected
            // Persist so subsequent launches don't re-detect (the OS language
            // might have changed, and we want to honour a manual override).
            defaults.set(detected.rawValue, forKey: Key.appLanguage)
        }
    }

    // MARK: - Language switching

    func setLanguage(_ newLanguage: Language) {
        language = newLanguage
    }

    // MARK: - String resolution

    /// Returns the translated string for `key` in the current language,
    /// falling back to English, then to the raw key if neither table has it.
    subscript(_ key: String) -> String {
        table(for: language)[key]
            ?? table(for: .english)[key]
            ?? key
    }

    /// Format-string variant. Passes `args` to `String(format:)` after
    /// resolving the template for the current language.
    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = self[key]
        return String(format: template, arguments: args)
    }

    // MARK: - Translation table dispatch

    private func table(for lang: Language) -> [String: String] {
        switch lang {
        case .english: return LocalizationManager.en
        case .turkish: return LocalizationManager.tr
        case .spanish: return LocalizationManager.es
        case .german:  return LocalizationManager.de
        case .italian: return LocalizationManager.it
        case .french:  return LocalizationManager.fr
        }
    }
}
