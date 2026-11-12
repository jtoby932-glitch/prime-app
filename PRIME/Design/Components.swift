import SwiftUI
import UIKit

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.padding
    var raised = false
    var highlight: Color? = nil

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
                    .strokeBorder(
                        LinearGradient(colors: [(highlight ?? Color.white).opacity(highlight == nil ? 0.08 : 0.5), Theme.border.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

extension View {
    func primeCard(padding: CGFloat = Theme.padding, raised: Bool = false, highlight: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, raised: raised, highlight: highlight))
    }

    /// Standard screen background with faint navy light from the top.
    func primeBackground() -> some View {
        background(Theme.backdrop)
    }
}

// MARK: - Headers

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.primeTitle3)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentHighlight)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stats

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = Theme.accentHighlight
    /// When set, the number counts up from zero on first appearance.
    var numeric: Double? = nil
    var format: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Group {
                if let numeric, let format {
                    CountUp(value: numeric, format: format)
                } else {
                    Text(value)
                }
            }
            .font(.primeNumber(26))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
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

extension StatTile {
    /// A tile whose whole number counts up.
    init(count: Int, label: String, symbol: String? = nil, tint: Color = Theme.accentHighlight) {
        self.init(value: "\(count)", label: label, symbol: symbol, tint: tint, numeric: Double(count), format: { "\(Int($0.rounded()))" })
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
            .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(minHeight: compact ? 38 : 50)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: kind == .primary ? Theme.accent.opacity(configuration.isPressed ? 0.15 : 0.35) : .clear, radius: 14, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.textPrimary
        case .destructive: return Theme.danger
        case .quiet: return Theme.accentHighlight
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(Theme.accentGradient)
        case .secondary: return AnyShapeStyle(Theme.field)
        case .destructive: return AnyShapeStyle(Theme.danger.opacity(0.12))
        case .quiet: return AnyShapeStyle(Theme.accentSoft)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return .white.opacity(0.18)
        case .secondary: return Theme.borderStrong
        case .destructive: return Theme.danger.opacity(0.3)
        case .quiet: return Theme.accent.opacity(0.3)
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
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Chips and tags

struct Chip: View {
    let title: String
    var symbol: String? = nil
    var isSelected = false
    var count: Int? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.medium))
                if let count {
                    Text("\(count)").font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.8) : Theme.textTertiary)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? .white.opacity(0.18) : Theme.border, lineWidth: 1))
            .animation(.easeOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct Tag: View {
    let text: String
    var color: Color = Theme.textSecondary
    var filled = false
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(filled ? Theme.onAccent : color)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(filled ? color : color.opacity(0.13)))
    }
}

// MARK: - Empty and loading states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(Theme.border, lineWidth: 1).frame(width: 84, height: 84)
                Circle().fill(Theme.accentSoft).frame(width: 62, height: 62)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accentHighlight)
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
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }
}

/// The PRIME mark drawing itself in, used while things load.
struct LoadingMark: View {
    var size: CGFloat = 54
    @Environment(\.motion) private var motion
    @State private var drawn: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            PrimeMark().fill(Theme.accent.opacity(0.12))
            PrimeMark()
                .trim(from: 0, to: motion.allowsAnimation ? drawn : 1)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(pulse ? 0.6 : 0.2), radius: pulse ? 18 : 8)
        .onAppear {
            guard motion.allowsAnimation else { return }
            withAnimation(.easeInOut(duration: 1.1)) { drawn = 1 }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Progress

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.accentGradient)
    @Environment(\.motion) private var motion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.field, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, motion.allowsAnimation ? shown : progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(motion.animation(.spring(response: 0.9, dampingFraction: 0.85))) { shown = progress } }
        .onChange(of: progress) { _, value in withAnimation(motion.animation()) { shown = value } }
    }
}

struct ProgressBar: View {
    var progress: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.accentGradient)
    var height: CGFloat = 6
    @Environment(\.motion) private var motion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let value = motion.allowsAnimation ? shown : progress
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, value))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(motion.animation(.spring(response: 0.8, dampingFraction: 0.86)).map { $0.delay(0.1) }) { shown = progress } }
        .onChange(of: progress) { _, value in withAnimation(motion.animation()) { shown = value } }
        .accessibilityElement()
        .accessibilityValue(Format.percent(progress))
    }
}

// MARK: - Avatar and icons

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
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct IconBubble: View {
    let symbol: String
    var tint: Color = Theme.accentHighlight
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(tint.opacity(0.14))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1)
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
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

/// A small label/value pair used in breakdowns.
struct MetricRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(valueColor)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The PRIME mark: a rising peak cut from a square.
struct PrimeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.74, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.5))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.26, y: rect.minY + h))
        path.closeSubpath()
        return path
    }
}

struct PrimeWordmark: View {
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: size * 0.2) {
            PrimeMark()
                .fill(Theme.accentGradient)
                .frame(width: size * 0.9, height: size * 0.9)
            Text("PRIME")
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .tracking(size * 0.04)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement()
        .accessibilityLabel("PRIME")
    }
}

// MARK: - Flow layout

/// Wraps children onto new lines when they run out of width (tags, chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
