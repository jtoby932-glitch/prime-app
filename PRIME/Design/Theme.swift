import SwiftUI

enum Theme {
    // Surfaces
    static let background = Color(hex: 0x050506)
    static let surface = Color(hex: 0x0D0D0F)
    static let card = Color(hex: 0x151518)
    static let cardRaised = Color(hex: 0x1C1C20)
    static let field = Color(hex: 0x232328)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.14)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9A9AA3)
    static let textTertiary = Color(hex: 0x5E5E67)

    // Brand
    static let accent = Color(hex: 0xC8FF3C)
    static let accentDeep = Color(hex: 0x8FCB12)
    static let onAccent = Color(hex: 0x0A0C02)
    static let accentSoft = Color(hex: 0xC8FF3C).opacity(0.14)

    // Status
    static let danger = Color(hex: 0xFF5D5D)
    static let warning = Color(hex: 0xFFB547)
    static let info = Color(hex: 0x6CC6FF)

    /// Routine colours.
    static let palette: [Color] = [
        Color(hex: 0xC8FF3C), Color(hex: 0x6CC6FF), Color(hex: 0xFF8A5C),
        Color(hex: 0xB79CFF), Color(hex: 0xFF6FA8), Color(hex: 0x5CE1C6),
    ]

    static func planColor(_ index: Int) -> Color { palette[((index % palette.count) + palette.count) % palette.count] }

    static let accentGradient = LinearGradient(colors: [Color(hex: 0xDFFF7A), accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardGradient = LinearGradient(colors: [Color(hex: 0x19191D), Color(hex: 0x121215)], startPoint: .top, endPoint: .bottom)

    // Geometry
    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 14
    static let padding: CGFloat = 16
    static let gutter: CGFloat = 20
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension RankTier {
    var color: Color {
        switch self {
        case .beginner: return Color(hex: 0x8C93A1)
        case .bronze: return Color(hex: 0xD08B57)
        case .silver: return Color(hex: 0xD5DCE6)
        case .gold: return Color(hex: 0xF2C94C)
        case .elite: return Theme.accent
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .beginner: colors = [Color(hex: 0xB4BAC6), Color(hex: 0x5F6573)]
        case .bronze: colors = [Color(hex: 0xF2B485), Color(hex: 0x8E5126)]
        case .silver: colors = [Color(hex: 0xFFFFFF), Color(hex: 0x8D96A3)]
        case .gold: colors = [Color(hex: 0xFFE89A), Color(hex: 0xB8860B)]
        case .elite: colors = [Color(hex: 0xEFFFB8), Theme.accent, Color(hex: 0x4E8F00)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var glyph: String {
        switch self {
        case .beginner: return "circle.dotted"
        case .bronze: return "1.circle.fill"
        case .silver: return "2.circle.fill"
        case .gold: return "3.circle.fill"
        case .elite: return "crown.fill"
        }
    }
}

// MARK: - Typography

extension Font {
    /// Big condensed numerals for stats and timers.
    static func primeNumber(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default).width(.condensed)
    }

    static let primeLargeTitle = Font.system(.largeTitle, design: .default, weight: .heavy).width(.condensed)
    static let primeTitle = Font.system(.title2, design: .default, weight: .bold)
    static let primeHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let primeBody = Font.system(.body)
    static let primeCaption = Font.system(.caption, design: .default, weight: .medium)
    static let primeEyebrow = Font.system(.caption2, design: .default, weight: .bold)
}

extension View {
    /// Small uppercase label used above sections and stats.
    func eyebrow() -> some View {
        font(.primeEyebrow)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }
}
