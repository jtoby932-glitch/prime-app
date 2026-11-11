import SwiftUI
import UIKit

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.padding
    var raised = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(raised ? AnyShapeStyle(Theme.cardRaised) : AnyShapeStyle(Theme.cardGradient))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func primeCard(padding: CGFloat = Theme.padding, raised: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, raised: raised))
    }

    /// Standard screen background.
    func primeBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Headers

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .default, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stats

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.primeNumber(28))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.primeCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .primeCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

struct PrimeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, quiet }
    var kind: Kind = .primary
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(minHeight: compact ? 38 : 50)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .strokeBorder(kind == .secondary ? Theme.strokeStrong : .clear, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.textPrimary
        case .destructive: return Theme.danger
        case .quiet: return Theme.accent
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(Theme.accentGradient)
        case .secondary: return AnyShapeStyle(Theme.field)
        case .destructive: return AnyShapeStyle(Theme.danger.opacity(0.14))
        case .quiet: return AnyShapeStyle(Theme.accentSoft)
        }
    }
}

extension ButtonStyle where Self == PrimeButtonStyle {
    static var primePrimary: PrimeButtonStyle { PrimeButtonStyle(kind: .primary) }
    static var primeSecondary: PrimeButtonStyle { PrimeButtonStyle(kind: .secondary) }
    static var primeDestructive: PrimeButtonStyle { PrimeButtonStyle(kind: .destructive) }
    static func prime(_ kind: PrimeButtonStyle.Kind, compact: Bool = false) -> PrimeButtonStyle { PrimeButtonStyle(kind: kind, compact: compact) }
}

/// Subtle press feedback for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var symbol: String? = nil
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.field))
            )
            .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct Tag: View {
    let text: String
    var color: Color = Theme.textSecondary
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Theme.onAccent : color)
            .background(Capsule().fill(filled ? color : color.opacity(0.12)))
    }
}

// MARK: - Empty states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 64, height: 64)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.primeHeadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.prime(.primary, compact: true))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

// MARK: - Progress

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(Theme.field, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
    }
}

struct ProgressBar: View {
    var progress: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.accent)
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, progress))))
                    .opacity(progress > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
        .accessibilityElement()
        .accessibilityValue(Format.percent(progress))
    }
}

// MARK: - Tier badge

/// A faceted shield used for rank tiers.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.95, y: rect.minY + h * 0.14))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.maxY),
                          control: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.72))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.14),
                          control: CGPoint(x: rect.minX + w * 0.02, y: rect.minY + h * 0.72))
        path.closeSubpath()
        return path
    }
}

struct TierBadgeView: View {
    let tier: RankTier
    var size: CGFloat = 44
    var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine = false

    var body: some View {
        ZStack {
            ShieldShape()
                .fill(tier.gradient)
                .overlay(ShieldShape().stroke(.white.opacity(0.35), lineWidth: max(1, size / 40)))
            ShieldShape()
                .fill(.black.opacity(0.18))
                .padding(size * 0.12)
            Image(systemName: tier.glyph)
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(.black.opacity(0.72))
                .offset(y: -size * 0.03)
            if tier == .elite && !dimmed && !reduceMotion && size > 60 {
                ShieldShape()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                    .offset(x: shine ? size : -size)
                    .clipShape(ShieldShape())
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) { shine = true }
                    }
            }
        }
        .frame(width: size, height: size * 1.12)
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.35 : 1)
        .shadow(color: tier == .elite && !dimmed ? Theme.accent.opacity(0.45) : .black.opacity(0.4), radius: size / 6, y: size / 20)
        .accessibilityElement()
        .accessibilityLabel("\(tier.name) tier")
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let data: Data?
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.accentGradient
                    Text(initials.isEmpty ? "P" : initials)
                        .font(.system(size: size * 0.38, weight: .heavy))
                        .foregroundStyle(Theme.onAccent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Misc

struct IconBubble: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(tint.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct InlineError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.danger)
    }
}

struct DividerLine: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }
}
