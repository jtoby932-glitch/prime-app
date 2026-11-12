import Charts
import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.bodyModel) private var model
    @Environment(\.motion) private var motion
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query private var rankings: [PerformanceRanking]
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var side: AnatomySide = .front

    private var profile: UserProfile? { profiles.first }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }
    private var samples: [SetSample] { store.history.samples(for: exercise.slug) }
    private var timed: Bool { exercise.guide.tracking == .time }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero.appear(0)
                    actions.appear(1)
                    if !samples.isEmpty { performance.appear(2) }
                    sectionJumper(proxy)
                    ExerciseGuideSections(exercise: exercise)
                    if exercise.isCustom { customActions }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
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
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(exercise.isFavourite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .onAppear {
            profile?.noteViewed(exercise.slug)
            side = AnatomyFigure.figure(model).bestSide(for: exercise.primaryMuscles)
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

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                AnatomyCanvas(side: side, primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, model: model)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .id(side)
                    .transition(motion.allowsMovement ? .scale(scale: 0.92).combined(with: .opacity) : .opacity)
                Picker("View", selection: $side.animation(motion.animation())) {
                    ForEach(AnatomySide.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Works \(exercise.primaryMuscleSummary)" + (exercise.secondaryMuscles.isEmpty ? "" : ", assisted by \(exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))"))

            HStack(spacing: 14) {
                legend(color: Theme.accent, text: "Primary")
                legend(color: Theme.accentHighlight.opacity(0.42), text: "Secondary")
            }
            Text(exercise.name).font(.primeTitle).foregroundStyle(Theme.textPrimary)
            FlowLayout(spacing: 6) {
                Tag(text: exercise.equipment.displayName, color: Theme.accentHighlight, symbol: exercise.equipment.symbol)
                Tag(text: exercise.mechanic.displayName)
                Tag(text: exercise.difficulty.displayName)
                if exercise.guide.unilateral { Tag(text: "Unilateral") }
                if !exercise.guide.pattern.isEmpty { Tag(text: exercise.guide.pattern) }
                if exercise.isCustom { Tag(text: "Custom", color: Theme.accentHighlight) }
            }
        }
        .primeHero(tint: Theme.accent, padding: 16)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            if let session = appState.activeSession {
                Button {
                    WorkoutService.addExercise(exercise, to: session, restSeconds: profile?.defaultRestSeconds ?? 90, context: context, history: store.history)
                    Haptics.success()
                    appState.show(Toast(title: "Added to workout", message: exercise.name, style: .success))
                } label: { Label("Add to current workout", systemImage: "plus.circle.fill") }
                    .buttonStyle(.primePrimary)
            } else {
                Button {
                    appState.startWorkout(with: exercise, restSeconds: profile?.defaultRestSeconds ?? 90, context: context, store: store)
                } label: { Label("Start workout with this", systemImage: "play.fill") }
                    .buttonStyle(.primePrimary)
            }
            HStack(spacing: 10) {
                if !plans.isEmpty {
                    Menu {
                        ForEach(plans) { plan in Button(plan.name) { add(to: plan) } }
                    } label: {
                        Label("Add to routine", systemImage: "text.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.field))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                if exercise.isRanked {
                    Button { appState.rankEntry = RankEntryRequest(exerciseSlug: exercise.slug) } label: {
                        Label("Log ranked lift", systemImage: "shield.lefthalf.filled").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prime(.secondary, compact: true))
                }
            }
        }
    }

    private func add(to plan: WorkoutPlan) {
        let position = (plan.entries.map(\.position).max() ?? -1) + 1
        let rest = profile?.defaultRestSeconds ?? 90
        let entry = PlannedExercise(position: position, exercise: exercise, targetSets: 3,
                                    targetReps: timed ? 30 : (exercise.mechanic == .compound ? 8 : 12), restSeconds: rest)
        context.insert(entry)
        entry.plan = plan
        try? context.save()
        Haptics.success()
        appState.show(Toast(title: "Added to \(plan.name)", message: "3 sets of \(entry.targetReps)\(timed ? " s" : "")", style: .success))
    }

    // MARK: Performance

    private var performance: some View {
        let records = store.history.records(for: exercise.slug)
        let progression = timed ? Analytics.repProgression(samples) : Analytics.oneRepMaxProgression(samples)
        let rank = RankingService.rank(for: exercise, history: store.history, submissions: rankings, scale: profile?.tierScale ?? 1)
        let insights = InsightEngine.exerciseInsights(slug: exercise.slug, name: exercise.name, samples: samples, isTimed: timed, now: Date())
        let last = store.history.lastPerformance(for: exercise.slug)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Your performance")
                NavigationLink(value: Route.exerciseHistory(exercise.slug)) {
                    Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                }
            }
            if exercise.isRanked {
                NavigationLink(value: Route.exerciseRank(exercise.slug)) {
                    HStack(spacing: 12) {
                        RankEmblem(tier: rank.currentTier, size: 46, dimmed: rank.currentResult == nil)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rank.currentResult.map { "\($0.placement.tier.name)" } ?? "Not ranked yet")
                                .font(.subheadline.weight(.bold)).foregroundStyle(rank.currentResult?.placement.tier.color ?? Theme.textPrimary)
                            if let result = rank.currentResult, let next = result.placement.tier.next {
                                ProgressBar(progress: result.placement.progress, tint: AnyShapeStyle(result.placement.tier.gradient), height: 4)
                                Text("\(Format.percent(result.placement.progress)) to \(next.name)").font(.caption).foregroundStyle(Theme.textSecondary)
                            } else {
                                Text(rank.failure?.message ?? "Top of the ladder").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                }
                .buttonStyle(PressableStyle())
            }
            HStack(spacing: 8) {
                if timed {
                    miniStat(records.longestHoldSeconds.map { Format.hold($0) } ?? "–", "Longest hold")
                } else if let best = records.bestOneRepMaxKg {
                    miniStat(Format.estimate(best, unit: unit), "Best est. 1RM")
                }
                if let heaviest = records.heaviestWeightKg, !timed {
                    miniStat(Format.weight(heaviest, unit: unit), "Heaviest")
                } else if !timed, let reps = samples.map(\.reps).max() {
                    miniStat("\(reps)", "Most reps")
                }
                miniStat("\(store.history.sessionCount(for: exercise.slug))", "Sessions")
            }
            if !last.isEmpty, let date = last.first?.date {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last session · \(date.relativeDayText)").eyebrow()
                    Text(last.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed) }.joined(separator: "   "))
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                }
            }
            if progression.count >= 2 { ProgressChart(points: progression, isWeight: !timed, unit: unit) }
            ForEach(insights) { InsightRow(insight: $0) }
            if !timed { repRecords }
        }
        .primeCard(padding: 16)
    }

    private var repRecords: some View {
        let table = RepRecords.table(samples).prefix(6)
        return VStack(alignment: .leading, spacing: 8) {
            if !table.isEmpty { Text("Rep records").eyebrow() }
            ForEach(Array(table.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.weightKg > 0 ? Format.weight(row.weightKg, unit: unit) : "Bodyweight")
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(row.reps) reps").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text(row.date.relativeDayText).font(.caption).foregroundStyle(Theme.textTertiary).frame(width: 86, alignment: .trailing)
                }
            }
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.primeNumber(19)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    // MARK: Guide navigation

    private func sectionJumper(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technique guide").font(.primeTitle3).foregroundStyle(Theme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GuideSection.allCases) { section in
                        Chip(title: section.shortTitle, symbol: section.symbol) {
                            withAnimation(motion.animation(.easeInOut(duration: 0.35))) { proxy.scrollTo(section, anchor: .top) }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private var customActions: some View {
        HStack(spacing: 10) {
            Button("Edit exercise") { showEditor = true }.buttonStyle(.primeSecondary)
            Button("Delete") { confirmDelete = true }.buttonStyle(.primeDestructive)
        }
    }
}

/// Line chart of an exercise's best result per session, with touch inspection.
struct ProgressChart: View {
    let points: [ExercisePoint]
    let isWeight: Bool
    let unit: WeightUnit
    @State private var selected: Date?

    var body: some View {
        let values = points.map { isWeight ? unit.fromKilograms($0.value) : $0.value }
        let floor = (values.min() ?? 0) * 0.9
        let ceiling = max(floor + 1, (values.max() ?? 1) * 1.05)
        let point = selected.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isWeight ? "Estimated 1RM per session" : "Best per session").eyebrow()
                Spacer()
                if let point {
                    Text((isWeight ? Format.estimate(point.value, unit: unit) : "\(Int(point.value))") + " · " + point.date.relativeDayText)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                }
            }
            Chart {
                ForEach(points) { item in
                    let value = isWeight ? unit.fromKilograms(item.value) : item.value
                    AreaMark(x: .value("Date", item.date), yStart: .value("Floor", floor), yEnd: .value("Value", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", item.date), y: .value("Value", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accentHighlight)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Date", item.date), y: .value("Value", value))
                        .foregroundStyle(Theme.accentHighlight)
                        .symbolSize(point?.id == item.id ? 70 : 18)
                }
                if let point {
                    RuleMark(x: .value("Selected", point.date)).foregroundStyle(Theme.borderStrong)
                }
            }
            .chartYScale(domain: floor...ceiling)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 150)
            .accessibilityLabel(isWeight ? "Estimated one-rep max over time" : "Best result over time")
        }
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
        let timed = samples.first?.isTimed ?? false
        let sessions = Dictionary(grouping: samples, by: \.sessionID)
            .map { SessionGroup(id: $0.key, sets: $0.value.sorted { $0.setIndex < $1.setIndex }) }
            .sorted { ($0.sets.first?.date ?? .distantPast) > ($1.sets.first?.date ?? .distantPast) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if sessions.isEmpty {
                    EmptyStateView(symbol: "clock", title: "No history yet", message: "Sets you log for \(exercise.name) will appear here.")
                }
                ForEach(sessions) { entry in
                    NavigationLink(value: Route.session(entry.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.sets.first?.date.relativeDayText ?? "").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if let best = entry.sets.compactMap(\.estimatedOneRepMax).max() {
                                    Text("est. 1RM " + Format.estimate(best, unit: unit)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                                }
                            }
                            Text(entry.sets.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed) }.joined(separator: "  ·  "))
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
            .padding(.bottom, 24)
        }
        .primeBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
