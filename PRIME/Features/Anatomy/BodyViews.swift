import SwiftUI

enum AnatomyPalette {
    static let body = Color(hex: 0x16213A)
    static let bodyLight = Color(hex: 0x1E2C4A)
    static let bodyDark = Color(hex: 0x0E1628)
    static let idle = Color(hex: 0x22314F)
    static let idleLight = Color(hex: 0x2B3C5E)
    static let outline = Color(hex: 0x05070B)

    static func fill(for emphasis: MuscleEmphasis) -> Color {
        switch emphasis {
        case .none: return idle
        case .secondary: return Theme.accentHighlight.opacity(0.42)
        case .primary: return Theme.accent
        case .heat(let level): return level <= 0 ? idle : Theme.accent.opacity(0.28 + 0.72 * min(1, level))
        }
    }

    /// How strongly a muscle is lit, 0 for idle up to 1 for primary.
    static func intensity(for emphasis: MuscleEmphasis) -> Double {
        switch emphasis {
        case .none: return 0
        case .secondary: return 0.45
        case .primary: return 1
        case .heat(let level): return max(0, min(1, level))
        }
    }

    /// Lighter at the top of the muscle, deeper at the bottom, so it reads as a form.
    static func gradient(for emphasis: MuscleEmphasis, in rect: CGRect) -> GraphicsContext.Shading {
        let level = intensity(for: emphasis)
        let top: Color = level == 0 ? idleLight : Color.white.opacity(0.18 + 0.1 * level)
        let base = fill(for: emphasis)
        return .linearGradient(Gradient(stops: [.init(color: top, location: 0), .init(color: base, location: 0.35), .init(color: base.opacity(level == 0 ? 1 : 0.9), location: 1)]),
                               startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY))
    }

    /// Draws the whole figure with depth: shaded body, lit muscles, glow on active ones.
    static func draw(view: AnatomyFigure.View2D, transform: CGAffineTransform, emphasis: [MuscleGroup: MuscleEmphasis], in context: inout GraphicsContext) {
        let lineWidth = max(0.5, transform.a * 2.2)
        var bounds = CGRect.null
        for part in view.base { bounds = bounds.union(part.applying(transform).boundingRect) }
        let bodyShading = GraphicsContext.Shading.linearGradient(Gradient(colors: [bodyLight, body, bodyDark]),
                                                                 startPoint: CGPoint(x: bounds.midX, y: bounds.minY), endPoint: CGPoint(x: bounds.midX, y: bounds.maxY))
        for part in view.base {
            let path = part.applying(transform)
            context.fill(path, with: bodyShading)
            context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: lineWidth)
        }
        // Glow pass first so it sits under every muscle outline.
        for shape in view.muscles {
            let level = intensity(for: emphasis[shape.muscle] ?? .none)
            guard level > 0.05 else { continue }
            let path = shape.path.applying(transform)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: max(2, transform.a * 7)))
                layer.fill(path, with: .color(Theme.accent.opacity(0.35 + 0.45 * level)))
            }
        }
        for shape in view.muscles {
            let item = emphasis[shape.muscle] ?? .none
            let level = intensity(for: item)
            let path = shape.path.applying(transform)
            context.fill(path, with: gradient(for: item, in: path.boundingRect))
            context.stroke(path, with: .color(outline), lineWidth: lineWidth)
            if level > 0.05 {
                context.stroke(path, with: .color(Theme.accentHighlight.opacity(0.25 + 0.55 * level)), lineWidth: lineWidth * 0.8)
            }
        }
    }
}

private struct BodyModelKey: EnvironmentKey {
    static let defaultValue = BodyModel.male
}

extension EnvironmentValues {
    /// The anatomy figure the user chose in Profile, injected once at the root.
    var bodyModel: BodyModel {
        get { self[BodyModelKey.self] }
        set { self[BodyModelKey.self] = newValue }
    }
}

/// Reads the chosen body model without each view querying the database.
struct BodyModelReader<Content: View>: View {
    @Environment(\.bodyModel) private var model
    let content: (BodyModel) -> Content

    init(@ViewBuilder content: @escaping (BodyModel) -> Content) { self.content = content }

    var body: some View { content(model) }
}

/// Fast, non-interactive anatomical drawing.
struct AnatomyCanvas: View {
    var side: AnatomySide
    var emphasis: [MuscleGroup: MuscleEmphasis]
    var model: BodyModel = .male
    var focusOn: [MuscleGroup]? = nil

    var body: some View {
        Canvas { context, size in
            let figure = AnatomyFigure.figure(model)
            let region = focusOn.flatMap { figure.focusRegion(for: $0, side: side) }
            let transform = figure.transform(fitting: size, region: region)
            let view = figure.view(side)
            AnatomyPalette.draw(view: view, transform: transform, emphasis: emphasis, in: &context)
        }
        .accessibilityHidden(true)
    }
}

extension AnatomyCanvas {
    /// Primary muscles at full strength, secondary ones lighter.
    init(side: AnatomySide, primary: [MuscleGroup], secondary: [MuscleGroup] = [], model: BodyModel = .male, focus: Bool = false) {
        var map: [MuscleGroup: MuscleEmphasis] = [:]
        for muscle in secondary { map[muscle] = .secondary }
        for muscle in primary { map[muscle] = .primary }
        self.init(side: side, emphasis: map, model: model, focusOn: focus ? primary : nil)
    }

    /// Heat from 0…1 per muscle.
    init(side: AnatomySide, heat: [MuscleGroup: Double], model: BodyModel = .male) {
        self.init(side: side, emphasis: heat.mapValues { MuscleEmphasis.heat($0) }, model: model, focusOn: nil)
    }
}

/// Small exercise thumbnail: the muscles it works, close up, with an equipment badge.
struct ExerciseIllustration: View {
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let equipment: Equipment
    var size: CGFloat = 56

    var body: some View {
        BodyModelReader { model in
            let figure = AnatomyFigure.figure(model)
            let side = figure.bestSide(for: primary.isEmpty ? secondary : primary)
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x0F1A30), Color(hex: 0x0A1222)], startPoint: .top, endPoint: .bottom))
                AnatomyCanvas(side: side, primary: primary, secondary: secondary, model: model, focus: true)
                    .padding(size * 0.06)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                if size >= 40 {
                    Image(systemName: equipment.symbol)
                        .font(.system(size: size * 0.15, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: size * 0.3, height: size * 0.3)
                        .background(Circle().fill(Theme.accent))
                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1.5))
                        .offset(x: size * 0.05, y: size * 0.05)
                }
            }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityHidden(true)
    }
}

extension ExerciseIllustration {
    init(exercise: Exercise, size: CGFloat = 56) {
        self.init(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, equipment: exercise.equipment, size: size)
    }
}

/// Tappable body for the muscle explorer.
struct InteractiveBodyView: View {
    var side: AnatomySide
    var model: BodyModel
    var emphasis: [MuscleGroup: MuscleEmphasis]
    @Binding var selection: MuscleGroup?
    @Environment(\.motion) private var motion

    var body: some View {
        let figure = AnatomyFigure.figure(model)
        GeometryReader { proxy in
            let transform = figure.transform(fitting: proxy.size)
            let view = figure.view(side)
            ZStack {
                // The shaded body and lit muscles are one drawing; only the selection sits on top.
                Canvas { context, _ in
                    AnatomyPalette.draw(view: view, transform: transform, emphasis: emphasis, in: &context)
                }
                .allowsHitTesting(false)
                ForEach(view.muscles) { shape in
                    let path = shape.path.applying(transform)
                    let isSelected = selection == shape.muscle
                    path
                        .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                        .overlay(
                            path.stroke(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 1.8)
                                .phaseAnimator([false, true], trigger: isSelected) { content, phase in
                                    content
                                        .shadow(color: Theme.accentHighlight.opacity(isSelected ? (phase ? 0.9 : 0.3) : 0), radius: phase ? 14 : 4)
                                } animation: { _ in motion.allowsMovement ? .easeInOut(duration: 0.45) : nil }
                        )
                        .contentShape(path)
                        .onTapGesture {
                            Haptics.selection()
                            withAnimation(motion.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                                selection = selection == shape.muscle ? nil : shape.muscle
                            }
                        }
                }
            }
        }
        .aspectRatio(figure.size.width / figure.size.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle map, \(side.anatomicalName.lowercased()) view" + (selection.map { ", \($0.displayName) selected" } ?? ""))
    }
}
