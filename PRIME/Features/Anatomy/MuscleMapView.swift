import SwiftData
import SwiftUI

/// Interactive anatomy: tap a muscle to learn what it does, which exercises train it
/// (directly or as a helper) and what you've recorded for it.
struct MuscleMapView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.motion) private var motion
    @Environment(\.bodyModel) private var model
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var side: AnatomySide
    @State private var selection: MuscleGroup?
    @State private var days = 7
    @State private var showAllPrimary = false
    @State private var showSecondary = false

    init(initial: MuscleGroup? = nil) {
        _selection = State(initialValue: initial)
        let side = initial.map { AnatomyFigure.figure(.male).bestSide(for: [$0]) } ?? .front
        _side = State(initialValue: side)
    }

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        let interval = DateInterval(start: Calendar.prime.date(byAdding: .day, value: -days, to: Date()) ?? Date(), end: Date())
        let samples = store.history.samples(in: interval)
        let sets = Analytics.setsByMuscle(samples)
        let top = Double(sets.values.max() ?? 0)
        let emphasis: [MuscleGroup: MuscleEmphasis] = top > 0 ? sets.mapValues { .heat(Double($0) / top) } : [:]
        let figure = AnatomyFigure.figure(model)

        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Picker("Side", selection: $side.animation(motion.animation(.spring(response: 0.55, dampingFraction: 0.8)))) {
                        ForEach(AnatomySide.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Range", selection: $days) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                }

                ZStack(alignment: .topTrailing) {
                    InteractiveBodyView(side: side, model: model, emphasis: emphasis, selection: $selection)
                        .id(side)
                        .padding(.vertical, 8)
                        .transition(motion.allowsMovement
                            ? .asymmetric(insertion: .modifier(active: FlipEffect(angle: side == .front ? -90 : 90), identity: FlipEffect(angle: 0)),
                                          removal: .modifier(active: FlipEffect(angle: side == .front ? 90 : -90), identity: FlipEffect(angle: 0)))
                            : .opacity)
                    Button { flip() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.cardRaised))
                    }
                    .accessibilityLabel("Turn the body around")
                }
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .primeCard()
                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    flip()
                })

                legend

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(figure.muscles(on: side)) { muscle in
                            Chip(title: muscle.shortName, isSelected: selection == muscle) {
                                withAnimation(motion.animation(.snappy)) { selection = selection == muscle ? nil : muscle }
                            }
                        }
                    }
                }

                if let muscle = selection {
                    detail(for: muscle, samples: samples, sets: sets[muscle] ?? 0)
                        .id(muscle)
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
        .navigationTitle(selection?.displayName ?? "Muscle map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let selection { side = figure.bestSide(for: [selection]) }
        }
        .onChange(of: selection) { _, _ in
            showAllPrimary = false
            showSecondary = false
        }
    }

    private func flip() {
        Haptics.selection()
        withAnimation(motion.animation(.spring(response: 0.55, dampingFraction: 0.8))) { side = side == .front ? .back : .front }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Text("Working sets, last \(days) days").font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(AnatomyPalette.idle).frame(width: 18, height: 10)
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(AnatomyPalette.fill(for: .heat(level))).frame(width: 18, height: 10)
                }
            }
            .accessibilityHidden(true)
            Text("More").font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func detail(for muscle: MuscleGroup, samples: [SetSample], sets: Int) -> some View {
        let info = MuscleInfo.of(muscle)
        let muscleSamples = samples.filter { $0.primaryMuscles.contains(muscle) }
        let lastTrained = store.history.samples.last { $0.primaryMuscles.contains(muscle) }?.date
        let primary = exercises.filter { $0.primaryMuscles.contains(muscle) }
        let secondary = exercises.filter { !$0.primaryMuscles.contains(muscle) && $0.secondaryMuscles.contains(muscle) }
        let shownPrimary = showAllPrimary ? primary : Array(primary.prefix(5))

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(muscle.displayName).font(.primeTitle).foregroundStyle(Theme.textPrimary)
                        Text(info.anatomicalName).font(.subheadline).foregroundStyle(Theme.accentHighlight)
                    }
                    Spacer()
                    Button { withAnimation(motion.animation(.snappy)) { selection = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.textTertiary)
                    }
                    .accessibilityLabel("Clear selection")
                }
                infoRow("mappin.and.ellipse", "Location", info.location)
                infoRow("bolt.fill", "Function", info.function)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trained by").eyebrow()
                    FlowLayout(spacing: 6) {
                        ForEach(info.movements, id: \.self) { Tag(text: $0, color: Theme.accentHighlight) }
                    }
                }
            }
            .primeCard(padding: 18)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your recorded activity, last \(days) days").eyebrow()
                HStack(spacing: 10) {
                    stat("\(sets)", "Sets")
                    stat("\(Analytics.totalReps(muscleSamples))", "Reps")
                    stat(lastTrained?.relativeDayText ?? "Never", "Last trained")
                }
                Text("Counts sets where this is a primary muscle. Helper involvement isn't added, so nothing is counted twice.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .primeCard(padding: 18)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Primary exercises").eyebrow()
                    Spacer()
                    Text("\(primary.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                }
                if primary.isEmpty {
                    Text("No exercises target this muscle directly yet.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                ForEach(shownPrimary) { exercise in exerciseLink(exercise) }
                if primary.count > 5 {
                    Button(showAllPrimary ? "Show fewer" : "Show all \(primary.count)") {
                        withAnimation(motion.animation(.snappy)) { showAllPrimary.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .primeCard(padding: 18)

            if !secondary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(motion.animation(.snappy)) { showSecondary.toggle() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Also works it as a helper").eyebrow()
                                Text("\(secondary.count) exercises use \(muscle.displayName.lowercased()) as a secondary muscle")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down").rotationEffect(.degrees(showSecondary ? 180 : 0)).foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showSecondary {
                        ForEach(secondary) { exercise in exerciseLink(exercise) }
                    }
                }
                .primeCard(padding: 18)
            }

            NavigationLink(value: Route.category(muscle)) {
                Label("Browse \(muscle.displayName.lowercased()) exercises", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primeSecondary)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func exerciseLink(_ exercise: Exercise) -> some View {
        NavigationLink(value: Route.exercise(exercise.slug)) {
            HStack {
                ExerciseRow(exercise: exercise)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func infoRow(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(symbol: symbol, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.primeNumber(20)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
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
