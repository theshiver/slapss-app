//
//  Theme.swift
//  slapss
//
//  App-wide color theme. A theme swaps the ACCENT layer only — the popover's
//  blobs/dots, pill, hero card tints, join button accent, and the full-screen
//  overlay's mesh palette. Neutral surfaces and ink (Tokens.paper*/ink*) are
//  intentionally theme-independent, as is light/dark mode, which continues to
//  follow the system appearance on an orthogonal axis.
//
//  Persistence lives in AppSettings.theme. Views consume colors via
//  `settings.theme.accents.<name>` so a theme change re-renders through the
//  normal ObservableObject invalidation path (static tokens wouldn't
//  reliably re-render sub-structs SwiftUI has decided to skip).
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    /// The original slapss look — peach/rose/sky popover, orange-magenta-purple mesh.
    case sunset
    /// Blues, lavender and sea green.
    case ocean
    /// Greens, sage and soft amber.
    case forest

    var id: String { rawValue }

    /// Localization key for the display name ("theme.sunset" etc.).
    var localizationKey: String { "theme.\(rawValue)" }

    /// Which MeshBackground palette the full-screen overlay uses. `.cool` and
    /// `.forest` already existed in MeshBackground (previously unused).
    var meshPalette: MeshBackground.Palette {
        switch self {
        case .sunset: return .sunset
        case .ocean:  return .cool
        case .forest: return .forest
        }
    }

    /// Flat swatch colors for theme pickers — the overlay mesh colors, which
    /// read as the theme's identity at a glance.
    var swatchColors: [Color] {
        switch self {
        case .sunset: return [Color(rgb: 0xE06B3A), Color(rgb: 0xA83A6B), Color(rgb: 0x5A3A8A)]
        case .ocean:  return [Color(rgb: 0x2D6CB0), Color(rgb: 0x5A3A8A), Color(rgb: 0x3A8A7A)]
        case .forest: return [Color(rgb: 0x3A8A5A), Color(rgb: 0x2D6C5A), Color(rgb: 0x5A6C3A)]
        }
    }

    var accents: Accents {
        switch self {
        case .sunset: return Self.sunsetAccents
        case .ocean:  return Self.oceanAccents
        case .forest: return Self.forestAccents
        }
    }

    /// The themed color set. Field names mirror the former Tokens entries;
    /// blob1/2/3 correspond to the old blobPeach/blobRose/blobSky roles
    /// (large → small in BlobsBackground).
    struct Accents {
        let blob1: Color
        let blob2: Color
        let blob3: Color

        let pillBg: Color
        let pillInk: Color
        let pulseDot: Color

        let heroTitle: Color
        let heroTime: Color
        let heroMeta: Color

        let heroBgLight: Color
        let heroBgDarkTop: Color
        let heroBgDarkBottom: Color

        let brandGradTop: Color
        let brandGradBottom: Color

        /// Join/primary button fill. Light mode stays neutral ink across all
        /// themes; dark mode carries the theme accent (matches v1 behavior
        /// where dark used the orange accent).
        let joinBg: Color

        /// Full-screen overlay primary CTA (Join/Complete) — gradient fill and
        /// glow. Flat colors (no light/dark variant): the overlay backdrop is
        /// always the dark mesh. Previously hardcoded green (0x2da14a) across
        /// all themes; themed in 1.8.1 so the CTA follows the accent and
        /// doesn't sink into the forest theme's green mesh.
        let overlayCtaTop: Color
        let overlayCtaBottom: Color
    }

    // MARK: - Palettes

    /// Identical to the pre-theming values — existing users see no change.
    private static let sunsetAccents = Accents(
        blob1: .themed(light: 0xFFE2C2, dark: 0xE8732A, darkAlpha: 0.45),
        blob2: .themed(light: 0xF7D3DF, dark: 0xB45A8C, darkAlpha: 0.40),
        blob3: .themed(light: 0xC9E3F5, dark: 0x508CB4, darkAlpha: 0.35),
        pillBg: .themed(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0xFFD6A8, darkAlpha: 0.12),
        pillInk: .themed(light: 0xA35A18, dark: 0xFFD6A8),
        pulseDot: .themed(light: 0xE8732A, dark: 0xFF9447),
        heroTitle: .themed(light: 0x3A2A1A, dark: 0xFBF2E1),
        heroTime: .themed(light: 0x7A5230, dark: 0xD8C5A8),
        heroMeta: .themed(light: 0x7A5230, dark: 0xC9B89A),
        heroBgLight: Color(rgb: 0xFFF7EC),
        heroBgDarkTop: Color(rgb: 0x2E2738),
        heroBgDarkBottom: Color(rgb: 0x25202D),
        brandGradTop: .themed(light: 0xFFE2C2, dark: 0xFFE2C2, darkAlpha: 0.85),
        brandGradBottom: .themed(light: 0xF7D3DF, dark: 0xF7D3DF, darkAlpha: 0.85),
        joinBg: .themed(light: 0x1F1D2B, dark: 0xFF9447),
        overlayCtaTop: Color(rgb: 0xE8732A),
        overlayCtaBottom: Color(rgb: 0xC2571F)
    )

    private static let oceanAccents = Accents(
        blob1: .themed(light: 0xC9E3F5, dark: 0x2E7CC4, darkAlpha: 0.45),
        blob2: .themed(light: 0xD9D3F2, dark: 0x7A5AC0, darkAlpha: 0.40),
        blob3: .themed(light: 0xC8EAE2, dark: 0x3A9A8A, darkAlpha: 0.35),
        pillBg: .themed(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0xA8D4FF, darkAlpha: 0.12),
        pillInk: .themed(light: 0x1B5E8A, dark: 0xA8D4FF),
        pulseDot: .themed(light: 0x2E7CC4, dark: 0x5CA8E8),
        heroTitle: .themed(light: 0x1A2A3A, dark: 0xE1EDFB),
        heroTime: .themed(light: 0x30527A, dark: 0xA8C4DC),
        heroMeta: .themed(light: 0x30527A, dark: 0x9AB6CC),
        heroBgLight: Color(rgb: 0xEFF6FC),
        heroBgDarkTop: Color(rgb: 0x27303E),
        heroBgDarkBottom: Color(rgb: 0x1F2733),
        brandGradTop: .themed(light: 0xC9E3F5, dark: 0xC9E3F5, darkAlpha: 0.85),
        brandGradBottom: .themed(light: 0xD9D3F2, dark: 0xD9D3F2, darkAlpha: 0.85),
        joinBg: .themed(light: 0x1F1D2B, dark: 0x5CA8E8),
        overlayCtaTop: Color(rgb: 0x2E7CC4),
        overlayCtaBottom: Color(rgb: 0x1F5C99)
    )

    private static let forestAccents = Accents(
        blob1: .themed(light: 0xD6EBD2, dark: 0x3E9A5C, darkAlpha: 0.45),
        blob2: .themed(light: 0xE9EFC8, dark: 0x8A9A3A, darkAlpha: 0.40),
        blob3: .themed(light: 0xFFE9C4, dark: 0xC08A3A, darkAlpha: 0.35),
        pillBg: .themed(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0xC2E8C2, darkAlpha: 0.12),
        pillInk: .themed(light: 0x2E6B42, dark: 0xC2E8C2),
        pulseDot: .themed(light: 0x3E9A5C, dark: 0x55B878),
        heroTitle: .themed(light: 0x1E3324, dark: 0xE6F5E2),
        heroTime: .themed(light: 0x3E6B4C, dark: 0xAECDAE),
        heroMeta: .themed(light: 0x3E6B4C, dark: 0x9FC09F),
        heroBgLight: Color(rgb: 0xF2F8EF),
        heroBgDarkTop: Color(rgb: 0x263229),
        heroBgDarkBottom: Color(rgb: 0x1E2A21),
        brandGradTop: .themed(light: 0xD6EBD2, dark: 0xD6EBD2, darkAlpha: 0.85),
        brandGradBottom: .themed(light: 0xE9EFC8, dark: 0xE9EFC8, darkAlpha: 0.85),
        joinBg: .themed(light: 0x1F1D2B, dark: 0x55B878),
        overlayCtaTop: Color(rgb: 0x3E9A5C),
        overlayCtaBottom: Color(rgb: 0x2E7444)
    )
}

// MARK: - Dynamic color helper

private extension Color {
    /// Appearance-dynamic color from two hex literals. Mirrors the
    /// `Color(light:dark:)` helper that is file-private to ContentView.swift —
    /// duplicated here (with a distinct name) rather than widening that
    /// helper's access.
    static func themed(
        light: UInt32, lightAlpha: Double = 1.0,
        dark: UInt32, darkAlpha: Double = 1.0
    ) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]) != nil
            return isDark
                ? NSColor(Color(rgb: dark, alpha: darkAlpha))
                : NSColor(Color(rgb: light, alpha: lightAlpha))
        })
    }
}

// MARK: - Theme picker (shared by Settings and Onboarding)

/// Three theme cards in a row: a stack of the theme's mesh swatch colors plus
/// the localized name. The selected card gets an accent border. Writes
/// straight to `AppSettings.theme`, so both call sites get live preview
/// behavior for free (the popover hero, onboarding hero, and number badges
/// all re-render from the same published property).
struct ThemeSwatchPicker: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTheme.allCases) { theme in
                ThemeSwatchCard(
                    theme: theme,
                    isSelected: settings.theme == theme,
                    label: lm[theme.localizationKey]
                ) {
                    settings.theme = theme
                }
            }
        }
    }
}

private struct ThemeSwatchCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: -6) {
                    ForEach(Array(theme.swatchColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    }
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(isSelected ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
