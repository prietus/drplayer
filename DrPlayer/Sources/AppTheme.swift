import SwiftUI

/// Theme system for DrPlayer. Defines UI accent colors while preserving
/// semantic colors (DR indicators, format badges) unchanged.
struct AppTheme {
    let name: String
    let accent: Color          // Primary accent (buttons, active tabs, selections)
    let secondaryAccent: Color // Charts, progress bars
    let highlight: Color       // Badges, producers tag, special elements
    let chartColors: [Color]   // Genre donut, visualizer palette

    // Semantic colors that stay constant across themes
    static let drGreen = Color.green
    static let drYellow = Color.yellow
    static let drOrange = Color.orange
    static let drRed = Color.red
}

// MARK: - Themes

extension AppTheme {
    /// Classic dark — cool blue steel, inspired by McIntosh amplifiers
    static let classic = AppTheme(
        name: "Classic",
        accent: Color(red: 0.35, green: 0.55, blue: 0.75),   // steel blue
        secondaryAccent: Color(red: 0.4, green: 0.6, blue: 0.7), // muted cyan
        highlight: Color(red: 0.7, green: 0.55, blue: 0.3),   // warm amber
        chartColors: [
            Color(red: 0.35, green: 0.55, blue: 0.75),
            Color(red: 0.5, green: 0.45, blue: 0.65),
            Color(red: 0.4, green: 0.6, blue: 0.7),
            Color(red: 0.3, green: 0.5, blue: 0.6),
            Color(red: 0.55, green: 0.5, blue: 0.6),
            Color(red: 0.45, green: 0.55, blue: 0.55),
        ]
    )

    /// Warm — analog tube amplifier tones
    static let warm = AppTheme(
        name: "Warm",
        accent: Color(red: 0.75, green: 0.55, blue: 0.3),     // warm amber
        secondaryAccent: Color(red: 0.65, green: 0.45, blue: 0.3), // copper
        highlight: Color(red: 0.8, green: 0.6, blue: 0.25),   // gold
        chartColors: [
            Color(red: 0.75, green: 0.55, blue: 0.3),
            Color(red: 0.65, green: 0.45, blue: 0.3),
            Color(red: 0.6, green: 0.5, blue: 0.35),
            Color(red: 0.7, green: 0.5, blue: 0.25),
            Color(red: 0.55, green: 0.45, blue: 0.35),
            Color(red: 0.6, green: 0.4, blue: 0.3),
        ]
    )

    /// Mono — minimal grayscale with silver accents, inspired by Bryston
    static let mono = AppTheme(
        name: "Mono",
        accent: Color(white: 0.7),                             // silver
        secondaryAccent: Color(white: 0.55),                   // gray
        highlight: Color(white: 0.85),                         // light silver
        chartColors: [
            Color(white: 0.7),
            Color(white: 0.55),
            Color(white: 0.45),
            Color(white: 0.6),
            Color(white: 0.5),
            Color(white: 0.65),
        ]
    )

    /// Vinyl — deep green and cream, inspired by vintage turntable aesthetics
    static let vinyl = AppTheme(
        name: "Vinyl",
        accent: Color(red: 0.3, green: 0.55, blue: 0.4),      // forest green
        secondaryAccent: Color(red: 0.35, green: 0.5, blue: 0.4), // sage
        highlight: Color(red: 0.7, green: 0.65, blue: 0.5),   // cream
        chartColors: [
            Color(red: 0.3, green: 0.55, blue: 0.4),
            Color(red: 0.35, green: 0.5, blue: 0.4),
            Color(red: 0.4, green: 0.5, blue: 0.35),
            Color(red: 0.3, green: 0.45, blue: 0.35),
            Color(red: 0.35, green: 0.45, blue: 0.4),
            Color(red: 0.4, green: 0.55, blue: 0.45),
        ]
    )

    static let allThemes: [AppTheme] = [.classic, .warm, .mono, .vinyl]
}

// MARK: - Theme Manager

@Observable
class ThemeManager {
    static let shared = ThemeManager()

    var current: AppTheme {
        didSet { UserDefaults.standard.set(current.name, forKey: "appTheme") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appTheme") ?? "Classic"
        current = AppTheme.allThemes.first { $0.name == saved } ?? .classic
    }
}
