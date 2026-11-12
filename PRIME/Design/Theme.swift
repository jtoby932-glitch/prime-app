import SwiftUI

// MARK: - Preferences that shape the look

enum AccentChoice: String, CaseIterable, Identifiable {
    case electric, glacier, violet

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .electric: return "Electric blue"
        case .glacier: return "Glacier"
        case .violet: return "Ultraviolet"
        }
    }
    var base: Color {
        switch self {
        case .electric: return Color(hex: 0x397BFF)
        case .glacier: return Color(hex: 0x2FA8E8)
        case .violet: return Color(hex: 0x7064FF)
        }
    }
    var highlight: Color {
        switch self {
        case .electric: return Color(hex: 0x69B7FF)
        case .glacier: return Color(hex: 0x8EE1FF)
        case .violet: return Color(hex: 0xB3A9FF)
        }
    }
    var deep: Color {
        switch self {
        case .electric: return Color(hex: 0x1F4FD1)
        case .glacier: return Color(hex: 0x1373B8)
        case .violet: return Color(hex: 0x4433D6)
        }
    }
}

enum AnimationLevel: String, CaseIterable, Identifiable {
    case full, reduced, off
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .full: return "Full"
        case .reduced: return "Reduced"
        case .off: return "Off"
        }
    }
}

enum BodyModel: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var displayName: String { self == .male ? "Male figure" : "Female figure" }
}

// MARK: - Tokens

enum Theme {
    /// Set at launch and when the user changes it; the root view is rebuilt on change.
    static var accentChoice: AccentChoice = .electric

    // Surfaces (black → navy depth)
    static let background = Color(hex: 0x05070B)
    static let surface = Color(hex: 0x0A1020)
    static let card = Color(hex: 0x101A2D)
    static let cardRaised = Color(hex: 0x15223A)
    static let field = Color(hex: 0x182742)
    static let border = Color(hex: 0x1D2B43)
    static let borderStrong = Color(hex: 0x2A3C5C)
    static let stroke = border
    static let strokeStrong = borderStrong

    // Text
    static let textPrimary = Color(hex: 0xF5F7FA)
    static let textSecondary = Color(hex: 0x8795AA)
    static let textTertiary = Color(hex: 0x56647A)

    // Accent
    static var accent: Color { accentChoice.base }
    static var accentHighlight: Color { accentChoice.highlight }
    static var accentDeep: Color { accentChoice.deep }
    static let onAccent = Color.white
    static var accentSoft: Color { accentChoice.base.opacity(0.16) }

    // Status
    static let success = Color(hex: 0x3DD9A4)
    static let danger = Color(hex: 0xFF5C6C)
    static let warning = Color(hex: 0xFFB547)
    static var info: Color { accentHighlight }

    /// Routine colours: distinct but tuned to sit on navy.
    static let palette: [Color] = [
        Color(hex: 0x397BFF), Color(hex: 0x3DD9A4), Color(hex: 0xFF8A5C),
        Color(hex: 0xA48BFF), Color(hex: 0xFF6FA8), Color(hex: 0x56D4F5),
    ]

    static func planColor(_ index: Int) -> Color { palette[((index % palette.count) + palette.count) % palette.count] }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentHighlight, accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Vertical fill for chart bars: lit at the top, deep at the base.
    static var barGradient: LinearGradient {
        LinearGradient(colors: [accentHighlight, accent, accentDeep.opacity(0.85)], startPoint: .top, endPoint: .bottom)
    }
    static var barGradientDim: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.45), accentDeep.opacity(0.3)], startPoint: .top, endPoint: .bottom)
    }

    static let cardGradient = LinearGradient(colors: [Color(hex: 0x13203A), Color(hex: 0x0E1728)], startPoint: .top, endPoint: .bottom)
    /// Deeper navy for hero cards; the accent light is layered on top by HeroSurface.
    static let heroGradient = LinearGradient(colors: [Color(hex: 0x172A52), Color(hex: 0x0E1830), Color(hex: 0x080D18)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Thin light along the top edge of raised surfaces.
    static var sheen: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.02), .clear], startPoint: .top, endPoint: .bottom)
    }
    /// The navy the frosted tab bar and sheets tint their blur with.
    static let glassTint = Color(hex: 0x070C16)

    /// Faint navy light from the top of the screen.
    static var backdrop: some View {
        ZStack {
            background
            RadialGradient(colors: [Color(hex: 0x10224A).opacity(0.55), .clear], center: .top, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    // Geometry: restrained radii, not pill-shaped
    static let radius: CGFloat = 18
    static let radiusSmall: CGFloat = 12
    static let padding: CGFloat = 16
    static let gutter: CGFloat = 18
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

// MARK: - Rank colours

extension RankTier {
    /// The colour used for text and accents.
    var color: Color {
        switch self {
        case .unranked: return Color(hex: 0x7A879C)
        case .bronze: return Color(hex: 0xD98A52)
        case .silver: return Color(hex: 0xD3DBE6)
        case .gold: return Color(hex: 0xF2C14E)
        case .platinum: return Color(hex: 0x9FE3DA)
        case .diamond: return Color(hex: 0x6EC8FF)
        case .elite: return Color(hex: 0x9C82FF)
        case .master: return Color(hex: 0xFFB648)
        }
    }

    var gradientStops: [Color] {
        switch self {
        case .unranked: return [Color(hex: 0x2A3650), Color(hex: 0x141D30)]
        case .bronze: return [Color(hex: 0xF3B886), Color(hex: 0xB8693A), Color(hex: 0x5E2F12)]
        case .silver: return [Color(hex: 0xFFFFFF), Color(hex: 0xB9C3D1), Color(hex: 0x5F6B7D)]
        case .gold: return [Color(hex: 0xFFF3B0), Color(hex: 0xF2C14E), Color(hex: 0x946205)]
        case .platinum: return [Color(hex: 0xF4FFFD), Color(hex: 0xA6E6DD), Color(hex: 0x3B8C86)]
        case .diamond: return [Color(hex: 0xE6F8FF), Color(hex: 0x6EC8FF), Color(hex: 0x1D58D8)]
        case .elite: return [Color(hex: 0xE6DCFF), Color(hex: 0x9172FF), Color(hex: 0x3A1CB0)]
        case .master: return [Color(hex: 0xFFEFB0), Color(hex: 0xF2B33D), Color(hex: 0x9A5A05)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Light colour behind the emblem during a reveal.
    var glow: Color {
        switch self {
        case .unranked: return Color(hex: 0x3A4A66)
        case .master: return Color(hex: 0xFF8A3D)
        default: return color
        }
    }

    /// 0...1 — higher tiers get more light, particles and haptics.
    var prestige: Double { Double(rawValue) / 7 }
}

// MARK: - Typography

extension Font {
    /// Condensed, tabular numerals for statistics, weights and timers.
    static func primeNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default).width(.condensed).monospacedDigit()
    }

    /// Big hero numerals: condensed and heavy, so a 3-digit stat reads at a glance.
    static func primeDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.condensed).monospacedDigit()
    }

    static let primeLargeTitle = Font.system(size: 32, weight: .heavy, design: .default)
    static let primeTitle = Font.system(.title2, design: .default, weight: .bold)
    static let primeTitle3 = Font.system(.title3, design: .default, weight: .semibold)
    static let primeHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let primeBody = Font.system(.body)
    static let primeCaption = Font.system(.caption, design: .default, weight: .medium)
    static let primeEyebrow = Font.system(.caption2, design: .default, weight: .semibold)
}

extension View {
    /// Small uppercase label used above sections and stats.
    func eyebrow(_ color: Color = Theme.textSecondary) -> some View {
        font(.primeEyebrow)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
