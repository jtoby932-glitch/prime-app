import Charts
import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @State private var showEditor = false
    @State private var confirmDelete = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var samples: [SetSample] { store.history.samples(for: exercise.slug) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if !samples.isEmpty { statsCard }
                lastSessionCard
                guidance(title: "How to do it", items: exercise.instructions, numbered: true, symbol: nil)
                guidance(title: "Technique", items: exercise.techniqueTips, numbered: false, symbol: "checkmark.circle.fill")
                guidance(title: "Common mistakes", items: exercise.commonMistakes, numbered: false, symbol: "xmark.circle.fill")
                alternatives
                if !samples.isEmpty { repRecords }
                actions
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exercise.isFavourite.toggle()
                    Haptics.selection()
                } label: {
                    Image(systemName: exercise.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(exercise.isFavourite ? Theme.warning : Theme.textPrimary)
                }
                .accessibilityLabel(exercise.isFavourite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .sheet(isPresented: $showEditor) { CustomExerciseEditor(existing: exercise) }
        .confirmationDialog("Delete \(exercise.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete exercise", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    context.delete(exercise)
                    try? context.save()
                }
            }
        } message: {
            Text("It will be removed from your routines. Sets you've already logged stay in your history.")
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                let levels = muscleLevels
                VStack(spacing: 4) {
                    AnatomyCanvas(side: .front, intensity: levels).frame(height: 210)
                    Text("Front").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
                VStack(spacing: 4) {
                    AnatomyCanvas(side: .back, intensity: levels).frame(height: 210)
                    Text("Back").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Works \(exercise.primaryMuscleSummary)" + (exercise.secondaryMuscles.isEmpty ? "" : ", also \(exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))"))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    legend(color: Theme.accent, text: "Primary")
                    legend(color: Theme.accent.opacity(0.45), text: "Secondary")
                }
                muscleLine(title: "Primary", muscles: exercise.primaryMuscles)
                if !exercise.secondaryMuscles.isEmpty {
                    muscleLine(title: "Secondary", muscles: exercise.secondaryMuscles)
                }
            }
            HStack(spacing: 6) {
                Tag(text: exercise.equipment.displayName, color: Theme.accent)
                Tag(text: exercise.mechanic.displayName)
                Tag(text: exercise.difficulty.displayName)
                if exercise.isCustom { Tag(text: "Custom", color: Theme.info) }
            }
        }
        .primeCard(padding: 18)
    }

    private var muscleLevels: [MuscleGroup: Double] {
        var levels: [MuscleGroup: Double] = [:]
        for muscle in exercise.secondaryMuscles { levels[muscle] = 0.3 }
        for muscle in exercise.primaryMuscles { levels[muscle] = 1 }
        return levels
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func muscleLine(title: String, muscles: [MuscleGroup]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 74, alignment: .leading)
            Text(muscles.map(\.displayName).joined(separator: ", ")).font(.subheadline).foregroundStyle(.white)
        }
    }

    private var statsCard: some View {
        let records = store.history.records(for: exercise.slug)
        let progression = Analytics.oneRepMaxProgression(samples)
        let rank = RankingService.rank(for: exercise, history: store.history, scale: profiles.first?.tierScale ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Your performance")
                NavigationLink(value: Route.exerciseHistory(exercise.slug)) {
                    Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            if exercise.isRanked {
                NavigationLink(value: Route.exerciseRank(exercise.slug)) {
                    HStack(spacing: 12) {
                        TierBadgeView(tier: rank.currentResult?.placement.tier ?? rank.peak?.placement.tier ?? .beginner, size: 40,
                                      dimmed: rank.currentResult == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rank.currentResult.map { "\($0.placement.tier.name) rank" } ?? "Not ranked yet")
                                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            Text(rank.failure?.message ?? rankLine(rank.currentResult))
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                }
                .buttonStyle(PressableStyle())
            }
            HStack(spacing: 10) {
                if let best = records.bestOneRepMaxKg {
                    miniStat(Format.estimate(best, unit: unit), "Best e1RM")
                }
                if let heaviest = records.heaviestWeightKg {
                    miniStat(Format.weight(heaviest, unit: unit), "Heaviest")
                } else if let reps = samples.map(\.reps).max() {
                    miniStat("\(reps)", "Most reps")
                }
                miniStat("\(store.history.sessionCount(for: exercise.slug))", "Sessions")
            }
            if progression.count >= 2 {
                let values = progression.map { unit.fromKilograms($0.value) }
                let floor = (values.min() ?? 0) * 0.9
                let ceiling = (values.max() ?? 1) * 1.05
                Chart(progression) { point in
                    LineMark(x: .value("Date", point.date), y: .value("e1RM", unit.fromKilograms(point.value)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                    AreaMark(x: .value("Date", point.date), yStart: .value("Floor", floor), yEnd: .value("e1RM", unit.fromKilograms(point.value)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    PointMark(x: .value("Date", point.date), y: .value("e1RM", unit.fromKilograms(point.value)))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(18)
                }
                .chartYScale(domain: floor...ceiling)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Estimated one-rep max over time")
                Text("Estimated 1RM per session (\(unit.symbol))").font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .primeCard(padding: 18)
    }

    private func rankLine(_ result: RankResult?) -> String {
        guard let result else { return "" }
        if let next = result.placement.tier.next {
            return "\(Format.percent(result.placement.progress)) of the way to \(next.name)"
        }
        return "Top tier reached"
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.primeNumber(20)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    @ViewBuilder
    private var lastSessionCard: some View {
        let last = store.history.lastPerformance(for: exercise.slug)
        if !last.isEmpty, let date = last.first?.date {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Previous workout").eyebrow()
                    Spacer()
                    Text(date.relativeDayText).font(.caption).foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(last.enumerated()), id: \.element.id) { index, set in
                    HStack {
                        Text("Set \(index + 1)").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Format.set(weightKg: set.weightKg, reps: set.reps, unit: unit))
                            .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                    }
                }
            }
            .primeCard()
        }
    }

    @ViewBuilder
    private func guidance(title: String, items: [String], numbered: Bool, symbol: String?) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: 12) {
                        if numbered {
                            Text("\(index + 1)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Theme.onAccent)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.accent))
                        } else if let symbol {
                            Image(systemName: symbol)
                                .foregroundStyle(symbol.hasPrefix("x") ? Theme.danger : Theme.accent)
                                .frame(width: 22)
                        }
                        Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .primeCard(padding: 18)
        }
    }

    @ViewBuilder
    private var alternatives: some View {
        let options = exercise.alternativeSlugs.compactMap { slug in allExercises.first { $0.slug == slug } }
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Alternatives")
                ForEach(options) { option in
                    NavigationLink(value: Route.exercise(option.slug)) {
                        HStack {
                            ExerciseRow(exercise: option)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .primeCard(padding: 18)
        }
    }

    private var repRecords: some View {
        let table = RepRecords.table(samples).prefix(8)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Rep records")
            ForEach(Array(table.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.weightKg > 0 ? Format.weight(row.weightKg, unit: unit) : "Bodyweight")
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                    Spacer()
                    Text("\(row.reps) reps").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text(row.date.relativeDayText).font(.caption).foregroundStyle(Theme.textTertiary).frame(width: 84, alignment: .trailing)
                }
            }
        }
        .primeCard(padding: 18)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let session = appState.activeSession {
                Button {
                    WorkoutService.addExercise(exercise, to: session, restSeconds: profiles.first?.defaultRestSeconds ?? 90, context: context, history: store.history)
                    Haptics.success()
                    appState.show(Toast(title: "Added to workout", message: exercise.name, style: .success))
                } label: { Label("Add to current workout", systemImage: "plus.circle.fill") }
                    .buttonStyle(.primePrimary)
            }
            if !plans.isEmpty {
                Menu {
                    ForEach(plans) { plan in
                        Button(plan.name) { add(to: plan) }
                    }
                } label: {
                    Label("Add to routine", systemImage: "text.badge.plus")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.field))
                        .foregroundStyle(.white)
                }
            }
            if exercise.isCustom {
                HStack(spacing: 10) {
                    Button("Edit exercise") { showEditor = true }.buttonStyle(.primeSecondary)
                    Button("Delete") { confirmDelete = true }.buttonStyle(.primeDestructive)
                }
            }
        }
    }

    private func add(to plan: WorkoutPlan) {
        let position = (plan.entries.map(\.position).max() ?? -1) + 1
        let rest = profiles.first?.defaultRestSeconds ?? 90
        let entry = PlannedExercise(position: position, exercise: exercise, targetSets: 3,
                                    targetReps: exercise.mechanic == .compound ? 8 : 12, restSeconds: rest)
        context.insert(entry)
        entry.plan = plan
        try? context.save()
        Haptics.success()
        appState.show(Toast(title: "Added to \(plan.name)", message: "3 sets of \(entry.targetReps)", style: .success))
    }
}

struct SessionGroup: Identifiable {
    let id: UUID
    let sets: [SetSample]
}

struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        let samples = store.history.samples(for: exercise.slug)
        let sessions = Dictionary(grouping: samples, by: \.sessionID)
            .map { SessionGroup(id: $0.key, sets: $0.value.sorted { $0.setIndex < $1.setIndex }) }
            .sorted { ($0.sets.first?.date ?? .distantPast) > ($1.sets.first?.date ?? .distantPast) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if sessions.isEmpty {
                    EmptyStateView(symbol: "clock", title: "No history yet", message: "Sets you log for \(exercise.name) will appear here.")
                }
                ForEach(sessions) { entry in
                    NavigationLink(value: Route.session(entry.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.sets.first?.date.relativeDayText ?? "").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                Spacer()
                                let best = entry.sets.compactMap(\.estimatedOneRepMax).max()
                                if let best { Text("e1RM " + Format.estimate(best, unit: unit)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                            }
                            Text(entry.sets.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit) }.joined(separator: "  ·  "))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .primeCard(padding: 14)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
