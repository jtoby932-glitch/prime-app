import SwiftUI

/// Fast, non-interactive body drawing. Muscles glow by intensity (0…1).
struct AnatomyCanvas: View {
    var side: AnatomySide
    var intensity: [MuscleGroup: Double]
    var focusOn: [MuscleGroup]? = nil
    var baseColor: Color = Color(hex: 0x24242A)
    var idleMuscle: Color = Color(hex: 0x34343C)
    var showDetail = true

    var body: some View {
        Canvas { context, size in
            let figure = AnatomyFigure.shared
            let region = focusOn.flatMap { figure.focusRegion(for: $0, side: side) }
            let transform = figure.transform(fitting: size, region: region)
            for part in figure.base {
                context.fill(part.applying(transform), with: .color(baseColor))
            }
            for shape in figure.shapes(for: side) {
                let level = intensity[shape.muscle] ?? 0
                let path = shape.path.applying(transform)
                context.fill(path, with: .color(idleMuscle))
                if level > 0 {
                    context.fill(path, with: .color(Theme.accent.opacity(0.22 + 0.78 * min(1, level))))
                }
                context.stroke(path, with: .color(Theme.background), lineWidth: max(0.6, transform.a * 1.1))
            }
            if showDetail {
                for line in figure.detail(for: side) {
                    context.stroke(line.applying(transform), with: .color(Theme.background.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: max(0.5, transform.a), lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Original exercise illustration: the muscles it works, highlighted, with the equipment.
struct ExerciseIllustration: View {
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let equipment: Equipment
    var size: CGFloat = 56
    var closeUp = true

    private var side: AnatomySide { AnatomyFigure.side(for: primary.isEmpty ? secondary : primary) }

    private var levels: [MuscleGroup: Double] {
        var levels: [MuscleGroup: Double] = [:]
        for muscle in secondary { levels[muscle] = 0.3 }
        for muscle in primary { levels[muscle] = 1 }
        return levels
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.surface)
            AnatomyCanvas(side: side, intensity: levels, focusOn: closeUp ? primary : nil, showDetail: size > 80)
                .padding(size * 0.08)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            Image(systemName: equipment.symbol)
                .font(.system(size: size * 0.17, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: size * 0.32, height: size * 0.32)
                .background(Circle().fill(Theme.accent))
                .offset(x: size * 0.04, y: size * 0.04)
                .opacity(size >= 44 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension ExerciseIllustration {
    init(exercise: Exercise, size: CGFloat = 56, closeUp: Bool = true) {
        self.init(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, equipment: exercise.equipment, size: size, closeUp: closeUp)
    }
}

/// Tappable body for the muscle map.
struct InteractiveBodyView: View {
    var side: AnatomySide
    var intensity: [MuscleGroup: Double]
    @Binding var selection: MuscleGroup?

    var body: some View {
        GeometryReader { proxy in
            let figure = AnatomyFigure.shared
            let transform = figure.transform(fitting: proxy.size)
            ZStack {
                ForEach(Array(figure.base.enumerated()), id: \.offset) { item in
                    item.element.applying(transform).fill(Color(hex: 0x24242A))
                }
                ForEach(figure.shapes(for: side)) { shape in
                    let path = shape.path.applying(transform)
                    let level = intensity[shape.muscle] ?? 0
                    let isSelected = selection == shape.muscle
                    path
                        .fill(fill(level: level, selected: isSelected))
                        .overlay(path.stroke(isSelected ? Color.white : Theme.background, lineWidth: isSelected ? 2 : 1.2))
                        .contentShape(path)
                        .onTapGesture {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selection = selection == shape.muscle ? nil : shape.muscle
                            }
                        }
                }
                ForEach(Array(figure.detail(for: side).enumerated()), id: \.offset) { item in
                    item.element.applying(transform)
                        .stroke(Theme.background.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(AnatomyFigure.shared.size.width / AnatomyFigure.shared.size.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle map, \(side.displayName.lowercased()) view")
    }

    private func fill(level: Double, selected: Bool) -> Color {
        if level <= 0 { return selected ? Color(hex: 0x4A4A55) : Color(hex: 0x34343C) }
        return Theme.accent.opacity(0.22 + 0.78 * min(1, level))
    }
}
