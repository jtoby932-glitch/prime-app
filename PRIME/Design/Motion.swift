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
            .offset(y: shown || !motion.allowsMovement ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if motion.allowsAnimation {
                    withAnimation(motion.animation(.spring(response: 0.5, dampingFraction: 0.86)).map { $0.delay(min(0.32, Double(index) * 0.045)) }) {
                        shown = true
                    }
                } else {
                    shown = true
                }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }
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
