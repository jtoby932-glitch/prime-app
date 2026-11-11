import Charts
import SwiftData
import SwiftUI

struct RankingsView: View {
    @Environment(TrainingStore.self) private var store
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var showBodyweight = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var scale: Double { profiles.first?.tierScale ?? 1 }

    var body: some View {
        let ranks = RankingService.ranks(exercises: exercises.filter(\.isRanked), history: store.history, scale: scale)
        let ranked = ranks.filter { $0.currentResult != nil }
        let unranked = ranks.filter { $0.currentResult == nil }
        let summary = RankingService.profileSummary(ranks)

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OverallRankCard(summary: summary, rankedCount: ranked.count)

                    if store.history.latestBodyweightKg == nil {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "scalemass.fill", tint: Theme.warning, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add your bodyweight").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                Text("Loaded lifts are ranked relative to bodyweight. Bodyweight exercises rank without it.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Add") { showBodyweight = true }.buttonStyle(.prime(.primary, compact: true))
                        }
                        .primeCard()
                    }

                    NavigationLink(value: Route.rankCalculator) {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "function", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rank calculator").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                Text("Enter any lift to see its tier and why").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        }
                        .primeCard()
                    }
                    .buttonStyle(PressableStyle())

                    if ranks.isEmpty {
                        EmptyStateView(symbol: "shield.lefthalf.filled", title: "No ranks yet",
                                       message: "Finish a workout with a ranked exercise and it will appear here with its tier.")
                            .primeCard()
                    }

                    if ranked.count >= 2 {
                        MuscleRankChart(ranks: ranked)
                    }

                    if !ranked.isEmpty {
                        SectionHeader(title: "Your lifts")
                        VStack(spacing: 8) {
                            ForEach(ranked) { rank in
                                NavigationLink(value: Route.exerciseRank(rank.exercise.slug)) {
                                    RankRow(rank: rank, unit: unit)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    if !unranked.isEmpty {
                        SectionHeader(title: "Waiting for a rank")
                        VStack(spacing: 8) {
                            ForEach(unranked) { rank in
                                NavigationLink(value: Route.exerciseRank(rank.exercise.slug)) {
                                    HStack(spacing: 12) {
                                        TierBadgeView(tier: rank.peak?.placement.tier ?? .beginner, size: 30, dimmed: true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rank.exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                            Text(rank.failure == .noSets && rank.peak != nil ? "No rankable sets in the last \(RankingService.currentWindowDays) days" : (rank.failure?.message ?? ""))
                                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                        }
                                        Spacer()
                                    }
                                    .primeCard(padding: 12)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label(RankingStandard.sourceLabel, systemImage: "info.circle").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        Text(RankingStandard.sourceDetail).font(.caption).foregroundStyle(Theme.textTertiary)
                        Text("Ranks use your best set from the last \(RankingService.currentWindowDays) days. Tiers are labels for performance on one lift, not a judgement of you.")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .primeBackground()
            .navigationTitle("Rankings")
            .sheet(isPresented: $showBodyweight) { BodyweightEntrySheet().presentationDetents([.medium]) }
            .primeDestinations()
            .workoutBarInset()
        }
    }
}

struct OverallRankCard: View {
    let summary: TrainingProfileSummary
    let rankedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                TierBadgeView(tier: summary.overall?.tier ?? .beginner, size: 84, dimmed: summary.overall == nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training profile").eyebrow()
                    Text(summary.overall.map { $0.tier.name } ?? "Unranked")
                        .font(.primeLargeTitle)
                        .foregroundStyle(summary.overall?.tier.color ?? Theme.textSecondary)
                    Text(summary.overall.map { "Average of \($0.count) ranked lift\($0.count == 1 ? "" : "s") · score \(Format.number($0.score, maxFractionDigits: 1)) / 5" } ?? "Rank a lift to build your profile")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if summary.overall != nil {
                HStack(spacing: 10) {
                    groupTile("Free weights", summary.freeWeights)
                    groupTile("Machines & cables", summary.machines)
                }
                HStack(spacing: 4) {
                    ForEach(RankTier.allCases) { tier in
                        let count = summary.tierCounts[tier] ?? 0
                        VStack(spacing: 4) {
                            Text("\(count)").font(.primeNumber(18)).foregroundStyle(count > 0 ? .white : Theme.textTertiary)
                            Capsule().fill(count > 0 ? tier.color : Theme.field).frame(height: 4)
                            Text(tier.name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .primeCard(padding: 18)
    }

    private func groupTile(_ title: String, _ group: TrainingProfileSummary.Group?) -> some View {
        HStack(spacing: 10) {
            TierBadgeView(tier: group?.tier ?? .beginner, size: 26, dimmed: group == nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(group.map { $0.tier.name } ?? "–").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

struct RankRow: View {
    let rank: ExerciseRank
    let unit: WeightUnit

    var body: some View {
        let result = rank.currentResult
        HStack(spacing: 12) {
            TierBadgeView(tier: result?.placement.tier ?? .beginner, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rank.exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if let result { Text(RankFormat.metric(result.metric, method: result.method)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                }
                if let result {
                    ProgressBar(progress: result.placement.progress, tint: AnyShapeStyle(result.placement.tier.gradient), height: 5)
                    Text(result.placement.tier.next.map { "\(Format.percent(result.placement.progress)) to \($0.name)" } ?? "Elite")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .primeCard(padding: 12)
    }
}

struct MuscleScore: Identifiable {
    let muscle: MuscleGroup
    let score: Double
    var id: MuscleGroup { muscle }
}

/// Average rank score per muscle group, coloured by tier.
struct MuscleRankChart: View {
    let ranks: [ExerciseRank]

    var body: some View {
        var scores: [MuscleGroup: [Double]] = [:]
        for rank in ranks {
            guard let score = rank.currentResult?.placement.score else { continue }
            for muscle in rank.exercise.primaryMuscles { scores[muscle, default: []].append(score) }
        }
        let rows = scores.map { MuscleScore(muscle: $0.key, score: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.score > $1.score }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By muscle group")
            Chart(rows) { row in
                BarMark(x: .value("Score", row.score), y: .value("Muscle", row.muscle.displayName))
                    .foregroundStyle(RankTier.forScore(row.score).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(RankTier.forScore(row.score).name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
            }
            .chartXScale(domain: 0...5.6)
            .chartXAxis {
                AxisMarks(values: [1.0, 2.0, 3.0, 4.0]) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let raw = value.as(Double.self), let tier = RankTier(rawValue: Int(raw.rounded())) {
                            Text(tier.name).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .frame(height: CGFloat(max(2, rows.count)) * 30 + 30)
        }
        .primeCard(padding: 18)
    }
}

enum RankFormat {
    static func metric(_ value: Double, method: RankingMethod) -> String {
        switch method {
        case .relativeLoad: return Format.ratio(value)
        case .repetitions: return "\(Format.number(value, maxFractionDigits: 1)) reps"
        case .unranked: return "–"
        }
    }

    /// Plain-language steps showing exactly how a rank was reached.
    static func explanation(_ result: RankResult, unit: WeightUnit, scale: Double, note: String) -> [String] {
        var lines: [String] = []
        let set = result.set
        let date = set.date.relativeDayText
        switch result.method {
        case .relativeLoad:
            lines.append("Best set: \(Format.weight(set.weightKg, unit: unit)) × \(set.reps) (\(date)).")
            if let e1rm = result.estimatedOneRepMaxKg {
                if set.reps == 1 {
                    lines.append("A single rep is already a one-rep max: \(Format.weight(e1rm, unit: unit)).")
                } else {
                    lines.append("Estimated 1RM (Epley) = \(Format.number(unit.fromKilograms(set.weightKg))) × (1 + \(set.reps) ÷ 30) = \(Format.weight(e1rm, unit: unit)).")
                }
                if let bodyweight = set.bodyweightKg {
                    lines.append("Bodyweight on that day: \(Format.weight(bodyweight, unit: unit)).")
                    lines.append("Relative strength = \(Format.number(unit.fromKilograms(e1rm), maxFractionDigits: 1)) ÷ \(Format.number(unit.fromKilograms(bodyweight), maxFractionDigits: 1)) = \(Format.ratio(result.metric)).")
                }
            }
        case .repetitions:
            if set.weightKg > 0 {
                lines.append("Best set: \(set.reps) reps with +\(Format.weight(set.weightKg, unit: unit)) (\(date)).")
                if let bodyweight = set.bodyweightKg {
                    lines.append("Weighted reps are converted with Epley: (\(Format.number(unit.fromKilograms(bodyweight))) + \(Format.number(unit.fromKilograms(set.weightKg)))) × (1 + \(set.reps) ÷ 30) ÷ \(Format.number(unit.fromKilograms(bodyweight))) → \(Format.number(result.metric, maxFractionDigits: 1)) bodyweight reps.")
                }
            } else {
                lines.append("Best set: \(set.reps) reps (\(date)).")
            }
        case .unranked:
            break
        }
        let placement = result.placement
        let floor = placement.tier == .beginner ? nil : result.thresholds[placement.tier.rawValue - 1]
        var tierLine = placement.tier == .beginner
            ? "Bronze starts at \(metric(result.thresholds[0], method: result.method)), so this is Beginner"
            : "\(placement.tier.name) starts at \(metric(floor ?? 0, method: result.method)), so this is \(placement.tier.name)"
        if let next = placement.tier.next, let threshold = placement.nextThreshold {
            tierLine += ", \(Format.percent(placement.progress)) of the way to \(next.name) at \(metric(threshold, method: result.method))."
        } else {
            tierLine += " — the top tier."
        }
        lines.append(tierLine)
        if result.usedCustomThresholds {
            lines.append("Using your own tier thresholds for this exercise.")
        } else if abs(scale - 1) > 0.001 {
            lines.append("Tiers are scaled to \(Format.percent(scale)) of the provisional defaults (Settings).")
        }
        if !note.isEmpty { lines.append(note) }
        return lines
    }
}
