import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable { case ar, en }
enum AppTheme: String, CaseIterable { case light, dark }
enum AppMode: String, CaseIterable { case wordChecker, tajweed }

struct ThemeColors: Equatable {
    let background, surface, border, gold, green, red, muted, currentWord, text, surfaceHigh: Color
    let listeningWordBackground, listeningWordBorder: Color
    static let light = ThemeColors(
        background: Color(hex: 0xFAF6F0), surface: Color(hex: 0xFFFDF8), border: Color(hex: 0xE8DFD3),
        gold: Color(hex: 0xB8860B), green: Color(hex: 0x2E8B57), red: Color(hex: 0xCD5C5C),
        muted: Color(hex: 0x8B7D6B), currentWord: Color(hex: 0xDAA520), text: Color(hex: 0x2C1810),
        surfaceHigh: Color(hex: 0xF2EDE5), listeningWordBackground: Color(hex: 0xDDECF7),
        listeningWordBorder: Color(hex: 0x7FA7C8))
    static let dark = ThemeColors(
        background: Color(hex: 0x0A0806), surface: Color(hex: 0x141210), border: Color(hex: 0x2A2520),
        gold: Color(hex: 0xDAA520), green: Color(hex: 0x3CB371), red: Color(hex: 0xE07070),
        muted: Color(hex: 0x9A8F82), currentWord: Color(hex: 0xF0C050), text: Color(hex: 0xF0E6D6),
        surfaceHigh: Color(hex: 0x1E1A16), listeningWordBackground: Color(hex: 0x17324A),
        listeningWordBorder: Color(hex: 0x537FA4))
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

@MainActor @Observable
final class AppState {
    static let shared = AppState()
    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "lang") } }
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var mode: AppMode = .wordChecker
    var blurMode: Bool { didSet { defaults.set(blurMode, forKey: "blurMode") } }
    var autoScrollSpeed: Int { didSet { defaults.set(autoScrollSpeed, forKey: "autoScrollSpeed") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var colors: ThemeColors { theme == .dark ? .dark : .light }
    var isArabic: Bool { language == .ar }
    private let defaults = UserDefaults.standard

    private init() {
        let deviceArabic = Locale.current.language.languageCode?.identifier == "ar"
        language = AppLanguage(rawValue: defaults.string(forKey: "lang") ?? "") ?? (deviceArabic ? .ar : .en)
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .light
        blurMode = defaults.object(forKey: "blurMode") as? Bool ?? false
        autoScrollSpeed = defaults.object(forKey: "autoScrollSpeed") as? Int ?? 1
        fontSize = min(42, max(16, defaults.object(forKey: "fontSize") as? Double ?? 28))
    }
}
