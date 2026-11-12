import SwiftUI

enum AnatomyPalette {
    static let body = Color(hex: 0x16213A)
    static let idle = Color(hex: 0x22314F)
    static let outline = Color(hex: 0x05070B)

    static func fill(for emphasis: MuscleEmphasis) -> Color {
        switch emphasis {
        case .none: return idle
        case .secondary: return Theme.accentHighlight.opacity(0.42)
        case .primary: return Theme.accent
        case .heat(let level): return level <= 0 ? idle : Theme.accent.opacity(0.28 + 0.72 * min(1, level))
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
            let lineWidth = max(0.5, transform.a * 2.2)
            for part in view.base {
                context.fill(part.applying(transform), with: .color(AnatomyPalette.body))
            }
            for shape in view.muscles {
                let path = shape.path.applying(transform)
                context.fill(path, with: .color(AnatomyPalette.fill(for: emphasis[shape.muscle] ?? .none)))
                context.stroke(path, with: .color(AnatomyPalette.outline), lineWidth: lineWidth)
            }
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
                ForEach(Array(view.base.enumerated()), id: \.offset) { item in
                    item.element.applying(transform).fill(AnatomyPalette.body)
                }
                ForEach(view.muscles) { shape in
                    let path = shape.path.applying(transform)
                    let isSelected = selection == shape.muscle
                    path
                        .fill(isSelected ? Theme.accentGradient : LinearGradient(colors: [AnatomyPalette.fill(for: emphasis[shape.muscle] ?? .none)], startPoint: .top, endPoint: .bottom))
                        .overlay(path.stroke(isSelected ? Color.white.opacity(0.9) : AnatomyPalette.outline, lineWidth: isSelected ? 1.6 : 1))
                        .shadow(color: isSelected ? Theme.accent.opacity(0.6) : .clear, radius: 8)
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
