import SwiftUI
import UIKit

/// Combines the system Reduce Motion setting with the user's in-app animation choice.
struct MotionPolicy: Equatable {
    var level: AnimationLevel

    static let full = MotionPolicy(level: .full)

    var allowsMovement: Bool { level == .full }
    var allowsAnimation: Bool { level != .off }

    /// A spring for full motion, a short fade for reduced, nothing when off.
    func animation(_ full: Animation = .spring(response: 0.45, dampingFraction: 0.85)) -> Animation? {
        switch level {
        case .full: return full
        case .reduced: return .easeInOut(duration: 0.18)
        case .off: return nil
        }
    }
}

private struct MotionKey: EnvironmentKey {
    static let defaultValue = MotionPolicy.full
}

extension EnvironmentValues {
    var motion: MotionPolicy {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}

/// Fades and lifts content in once, staggered by index. Never blocks touches.
struct AppearModifier: ViewModifier {
    let index: Int
    @Environment(\.motion) private var motion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !motion.allowsAnimation ? 1 : 0)
            .offset(y: shown || !motion.allowsMovement ? 0 : 18)
            .scaleEffect(shown || !motion.allowsMovement ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !shown else { return }
                if motion.allowsAnimation {
                    withAnimation(motion.animation(.spring(response: 0.55, dampingFraction: 0.82)).map { $0.delay(min(0.4, Double(index) * 0.055)) }) {
                        shown = true
                    }
                } else {
                    shown = true
                }
            }
    }
}

/// A soft light that moves across the content once, or keeps sweeping.
struct ShimmerModifier: ViewModifier {
    var repeats: Bool
    var color: Color
    @Environment(\.motion) private var motion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { proxy in
                if motion.allowsMovement {
                    LinearGradient(colors: [.clear, color.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6 - proxy.size.width * 0.3)
                        .rotationEffect(.degrees(18))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .mask(content)
        )
        .onAppear {
            guard motion.allowsMovement else { return }
            let sweep = Animation.easeInOut(duration: 1.6)
            withAnimation(repeats ? sweep.delay(1.8).repeatForever(autoreverses: false) : sweep.delay(0.4)) { phase = 1 }
        }
    }
}

/// A glow whose radius slowly breathes.
struct BreathingGlow: ViewModifier {
    var color: Color
    var radius: CGFloat
    @Environment(\.motion) private var motion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(up ? 0.75 : 0.35), radius: up ? radius : radius * 0.55)
            .onAppear {
                guard motion.allowsMovement else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }
    func shimmer(repeats: Bool = false, color: Color = .white) -> some View { modifier(ShimmerModifier(repeats: repeats, color: color)) }
    func breathingGlow(_ color: Color, radius: CGFloat = 24) -> some View { modifier(BreathingGlow(color: color, radius: radius)) }
}

/// Animates a number from zero on first appearance, then between values.
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

struct CountUp: View {
    let value: Double
    let format: (Double) -> String
    @Environment(\.motion) private var motion
    @State private var shown: Double = 0
    @State private var started = false

    var body: some View {
        CountingText(value: motion.allowsAnimation ? shown : value, format: format)
            .onAppear {
                guard !started else { return }
                started = true
                withAnimation(motion.animation(.easeOut(duration: 0.9))) { shown = value }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(motion.animation(.easeOut(duration: 0.5))) { shown = newValue }
            }
            .accessibilityLabel(format(value))
    }
}

/// Drives bars and lines from zero to full height once, then lets later data changes animate normally.
struct ChartGrowth: ViewModifier {
    @Binding var factor: Double
    var delay: Double = 0.15
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        content.onAppear {
            guard factor < 1 else { return }
            if motion.allowsAnimation {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(delay)) { factor = 1 }
            } else {
                factor = 1
            }
        }
    }
}

extension View {
    func chartGrowth(_ factor: Binding<Double>, delay: Double = 0.15) -> some View { modifier(ChartGrowth(factor: factor, delay: delay)) }
}

enum Haptics {
    /// Mirrors the user's preference; set at launch and when it changes.
    static var enabled = true

    static func tap() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thud() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { guard enabled else { return }; UISelectionFeedbackGenerator().selectionChanged() }
    /// A crisp tick for completing a set.
    static func setComplete() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9) }
    /// Two beats and a success note for a personal record.
    static func record() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { generator.impactOccurred(intensity: 1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// A short pattern that grows with the tier, used once per reveal.
    static func rankReveal(_ tier: RankTier) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: tier >= .platinum ? .heavy : .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.6 + 0.4 * tier.prestige)
        guard tier >= .gold else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { generator.impactOccurred(intensity: 0.7) }
        guard tier >= .diamond else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
