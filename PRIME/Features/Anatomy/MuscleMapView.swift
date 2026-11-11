import SwiftData
import SwiftUI

struct MuscleMapView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var side: AnatomySide = .front
    @State private var selection: MuscleGroup?
    @State private var days = 7
    @State private var showAllExercises = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        let interval = DateInterval(start: Calendar.prime.date(byAdding: .day, value: -days, to: Date()) ?? Date(), end: Date())
        let samples = store.history.samples(in: interval)
        let sets = Analytics.setsByMuscle(samples)
        // Roughly 10 hard sets per muscle per week is treated as "fully trained" for colouring.
        let target = 10.0 * Double(days) / 7
        let intensity = sets.mapValues { min(1, Double($0) / target) }

        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Picker("Side", selection: $side.animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8))) {
                        ForEach(AnatomySide.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Range", selection: $days) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                }

                ZStack {
                    InteractiveBodyView(side: side, intensity: intensity, selection: $selection)
                        .id(side)
                        .transition(.asymmetric(
                            insertion: .modifier(active: FlipEffect(angle: side == .front ? -90 : 90), identity: FlipEffect(angle: 0)),
                            removal: .modifier(active: FlipEffect(angle: side == .front ? 90 : -90), identity: FlipEffect(angle: 0))
                        ))
                }
                .frame(height: 430)
                .frame(maxWidth: .infinity)
                .primeCard()
                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) { side = side == .front ? .back : .front }
                })

                legend

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnatomyFigure.shared.muscles(on: side)) { muscle in
                            Chip(title: muscle.shortName, isSelected: selection == muscle) {
                                withAnimation(.snappy) { selection = selection == muscle ? nil : muscle }
                            }
                        }
                    }
                }

                if let muscle = selection {
                    detail(for: muscle, samples: samples, sets: sets[muscle] ?? 0)
                } else {
                    Text("Tap a muscle, or swipe the body to turn it around.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .primeBackground()
        .navigationTitle("Muscle map")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: side) { _, newSide in
            if let selection, selection.anatomySide != newSide, !AnatomyFigure.shared.muscles(on: newSide).contains(selection) {
                self.selection = nil
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Text("Sets in the last \(days) days").font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x34343C)).frame(width: 18, height: 10)
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.22 + 0.78 * level)).frame(width: 18, height: 10)
                }
            }
            .accessibilityHidden(true)
            Text("More").font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func detail(for muscle: MuscleGroup, samples: [SetSample], sets: Int) -> some View {
        let muscleSamples = samples.filter { $0.primaryMuscles.contains(muscle) }
        let lastTrained = store.history.samples.last { $0.primaryMuscles.contains(muscle) }?.date
        let targeting = exercises.filter { $0.primaryMuscles.contains(muscle) }
        let shown = showAllExercises ? targeting : Array(targeting.prefix(6))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(muscle.displayName).font(.primeTitle).foregroundStyle(.white)
                Spacer()
                Button { withAnimation { selection = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary) }
                    .accessibilityLabel("Clear selection")
            }
            HStack(spacing: 10) {
                stat("\(sets)", "Sets")
                stat(Format.volume(Analytics.totalVolume(muscleSamples), unit: unit, includeUnit: false), "Volume (\(unit.symbol))")
                stat(lastTrained?.relativeDayText ?? "Never", "Last trained")
            }
            Text("Exercises for \(muscle.displayName.lowercased())").eyebrow()
            ForEach(shown) { exercise in
                NavigationLink(value: Route.exercise(exercise.slug)) {
                    HStack {
                        ExerciseRow(exercise: exercise)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(PressableStyle())
            }
            if targeting.count > 6 {
                Button(showAllExercises ? "Show fewer" : "Show all \(targeting.count)") { withAnimation { showAllExercises.toggle() } }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .primeCard(padding: 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.primeNumber(20)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }
}

/// Turns the body around like a figure on a plinth.
struct FlipEffect: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(abs(angle) >= 90 ? 0 : 1)
    }
}
