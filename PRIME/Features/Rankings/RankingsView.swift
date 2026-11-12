import Charts
import SwiftData
import SwiftUI

struct RankingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @Query(sort: \PerformanceRanking.recordedAt) private var rankings: [PerformanceRanking]
    @State private var showBodyweight = false
    @State private var path: [Route] = []

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var scale: Double { profiles.first?.tierScale ?? 1 }

    var body: some View {
        let ranks = RankingService.ranks(exercises: exercises, history: store.history, submissions: rankings, scale: scale)
        let ranked = ranks.filter { $0.currentResult != nil }
        let waiting = ranks.filter { $0.currentResult == nil }
        let distribution = RankDistribution(tiers: ranked.map(\.currentTier))
        let close = RankingService.closeToRankingUp(ranked)
        let rankUps = RankingService.rankUps(rankings)

        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    LadderOverviewCard(distribution: distribution, peak: rankings.map(\.tier).max()).appear(0)

                    Button { appState.rankEntry = RankEntryRequest(exerciseSlug: nil) } label: {
                        Label("Log a ranked performance", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.primePrimary)
                    .appear(1)

                    if store.history.latestBodyweightKg == nil {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "scalemass.fill", tint: Theme.warning, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add your bodyweight").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                                Text("Loaded lifts rank relative to bodyweight. Bodyweight exercises rank without it.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Add") { showBodyweight = true }.buttonStyle(.prime(.primary, compact: true))
                        }
                        .primeCard()
                    }

                    if ranks.isEmpty {
                        EmptyStateView(symbol: "shield.lefthalf.filled", title: "No ranks yet",
                                       message: "Each lift earns its own rank, from Bronze to Master. Finish a workout with a ranked exercise or log a performance to see yours.")
                            .primeCard()
                    }

                    if !close.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Close to ranking up", subtitle: "60% or more of the way to the next tier")
                            ForEach(close.prefix(3)) { rank in
                                NavigationLink(value: Route.exerciseRank(rank.exercise.slug)) { CloseRankRow(rank: rank, unit: unit) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    if !ranked.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Your lifts", subtitle: "Current rank · best set in the last \(RankingService.currentWindowDays) days")
                            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, rank in
                                NavigationLink(value: Route.exerciseRank(rank.exercise.slug)) { RankRow(rank: rank) }
                                    .buttonStyle(PressableStyle())
                                    .appear(min(index, 8))
                            }
                        }
                    }

                    if !rankUps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionHeader(title: "Recent achievements")
                                NavigationLink(value: Route.rankHistory) {
                                    Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                                }
                            }
                            ForEach(rankUps.prefix(4)) { entry in
                                RankHistoryRow(entry: entry, unit: unit)
                            }
                        }
                        .primeCard(padding: 16)
                    }

                    if !waiting.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Waiting for a rank")
                            ForEach(waiting) { rank in
                                NavigationLink(value: Route.exerciseRank(rank.exercise.slug)) {
                                    HStack(spacing: 12) {
                                        RankEmblem(tier: rank.peak?.placement.tier ?? .unranked, size: 34, dimmed: true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rank.exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
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

                    NavigationLink(value: Route.methodology) {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "function", size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("How ranking works").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text("Formulas, thresholds and what counts").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        }
                        .primeCard(padding: 12)
                    }
                    .buttonStyle(PressableStyle())

                    Text("\(RankingStandard.sourceLabel). Ranks describe performance on one lift, not you.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .primeBackground()
            .navigationTitle("Rankings")
            .sheet(isPresented: $showBodyweight) { BodyweightEntrySheet().presentationDetents([.medium]) }
            .primeDestinations()
            .onChange(of: appState.pendingRoute) { _, route in
                guard let route else { return }
                path = [route]
                appState.pendingRoute = nil
            }
        }
    }
}

/// The whole ladder with how many lifts sit at each tier. No single overall rank on purpose.
struct LadderOverviewCard: View {
    let distribution: RankDistribution
    let peak: RankTier?
    @Environment(\.motion) private var motion
    @State private var shown = false

    var body: some View {
        let highest = distribution.highest
        let maxCount = max(1, distribution.tierCounts.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                RankEmblem(tier: highest ?? .unranked, size: 96, dimmed: highest == nil, animated: true, aura: true)
                    .scaleEffect(shown || !motion.allowsMovement ? 1 : 0.6)
                    .opacity(shown || !motion.allowsAnimation ? 1 : 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Highest current rank").eyebrow()
                    Text(highest?.name ?? "None yet")
                        .font(.primeLargeTitle)
                        .foregroundStyle(highest?.color ?? Theme.textSecondary)
                    Text("\(distribution.rankedCount) ranked lift\(distribution.rankedCount == 1 ? "" : "s")" + (peak.map { " · peak ever \($0.name)" } ?? ""))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            // Tier spread: a bar per tier, scaled to the busiest one.
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(RankTier.ranked.enumerated()), id: \.element) { index, tier in
                    let count = distribution.tierCounts[tier] ?? 0
                    let height = CGFloat(count) / CGFloat(maxCount)
                    VStack(spacing: 5) {
                        Text("\(count)").font(.primeNumber(14)).foregroundStyle(count > 0 ? Theme.textPrimary : Theme.textTertiary)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.field.opacity(0.6)).frame(height: 30)
                            RoundedRectangle(cornerRadius: 3).fill(tier.gradient)
                                .frame(height: max(count > 0 ? 4 : 0, 30 * (shown || !motion.allowsAnimation ? height : 0)))
                                .shadow(color: tier.glow.opacity(count > 0 ? 0.5 : 0), radius: 4)
                                .animation(motion.animation(.spring(response: 0.6, dampingFraction: 0.75)).map { $0.delay(0.25 + Double(index) * 0.05) }, value: shown)
                        }
                        RankEmblem(tier: tier, size: 26, dimmed: count == 0, aura: false)
                        Text(tier.name).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(count > 0 ? Theme.textSecondary : Theme.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RankTier.ranked.map { "\(distribution.tierCounts[$0] ?? 0) \($0.name)" }.joined(separator: ", "))
        }
        .primeHero(tint: highest?.glow ?? Theme.accent)
        .onAppear { withAnimation(motion.animation(.spring(response: 0.6, dampingFraction: 0.7)).map { $0.delay(0.1) }) { shown = true } }
    }
}

struct RankRow: View {
    let rank: ExerciseRank

    var body: some View {
        let result = rank.currentResult
        HStack(spacing: 12) {
            RankEmblem(tier: rank.currentTier, size: 42)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rank.exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    if let result {
                        Text(RankFormat.metric(result.metric, method: result.method)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let result {
                    ProgressBar(progress: result.placement.tier.next == nil ? 1 : result.placement.progress, tint: AnyShapeStyle(result.placement.tier.gradient), height: 5)
                    HStack {
                        Text(result.placement.tier.name).font(.caption2.weight(.bold)).foregroundStyle(result.placement.tier.color)
                        Spacer()
                        Text(result.placement.tier.next.map { "\(Format.percent(result.placement.progress)) to \($0.name)" } ?? "Top tier")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .primeCard(padding: 12)
    }
}

struct CloseRankRow: View {
    let rank: ExerciseRank
    let unit: WeightUnit

    var body: some View {
        let result = rank.currentResult
        let target = result.flatMap { NextTierTarget.make(for: $0, increment: unit.toKilograms(unit.increment)) }
        let next = rank.currentTier.next ?? .master
        HStack(spacing: 12) {
            MiniRing(progress: result?.placement.progress ?? 0, size: 44, tint: next.color)
            VStack(alignment: .leading, spacing: 5) {
                Text(rank.exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                TierPill(from: rank.currentTier, to: next)
                Text(RankFormat.targetText(target, unit: unit) ?? "").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 12)
    }
}

struct RankHistoryRow: View {
    let entry: PerformanceRanking
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            RankEmblem(tier: entry.tier, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(entry.tier.name) · " + RankFormat.performance(entry, unit: unit))
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.recordedAt.relativeDayText).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(entry.isSubmitted ? "Logged" : "Workout").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
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

    static func performance(_ entry: PerformanceRanking, unit: WeightUnit) -> String {
        if entry.method == .repetitions {
            return entry.weightKg > 0 ? "\(entry.reps) reps +\(Format.weight(entry.weightKg, unit: unit))" : "\(entry.reps) reps"
        }
        return "\(Format.weight(entry.weightKg, unit: unit)) × \(entry.reps)"
    }

    static func targetText(_ target: NextTierTarget?, unit: WeightUnit) -> String? {
        guard let target else { return nil }
        if let weight = target.weightKg, let oneRepMax = target.oneRepMaxKg {
            return "\(target.tier.name): about \(Format.weight(weight, unit: unit)) × \(target.reps) (est. 1RM \(Format.estimate(oneRepMax, unit: unit, decimals: 0)))"
        }
        if let reps = target.repsNeeded {
            return "\(target.tier.name): \(reps) bodyweight reps in a set"
        }
        return nil
    }

    /// Plain-language steps showing exactly how a rank was reached.
    static func explanation(_ result: RankResult, unit: WeightUnit, scale: Double) -> [String] {
        var lines: [String] = []
        let set = result.set
        let date = set.date.relativeDayText
        switch result.method {
        case .relativeLoad:
            lines.append("Best set: \(Format.weight(set.weightKg, unit: unit)) × \(set.reps) (\(date)).")
            if let e1rm = result.estimatedOneRepMaxKg {
                if set.isTestedMax {
                    lines.append("A single rep counts as a tested 1RM: \(Format.estimate(e1rm, unit: unit)).")
                } else {
                    lines.append("Estimated 1RM (Epley) = \(Format.number(unit.fromKilograms(set.weightKg))) × (1 + \(set.reps) ÷ 30) = \(Format.estimate(e1rm, unit: unit)). This is an estimate, not a tested max.")
                }
                if let bodyweight = set.bodyweightKg {
                    lines.append("Bodyweight used: \(Format.weight(bodyweight, unit: unit)).")
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
                lines.append("Best set: \(set.reps) bodyweight reps (\(date)).")
            }
        case .unranked:
            break
        }
        let placement = result.placement
        let floor = placement.tier == .unranked ? nil : result.thresholds[placement.tier.rawValue - 1]
        var tierLine = placement.tier == .unranked
            ? "Bronze starts at \(metric(result.thresholds[0], method: result.method)), so this is Unranked"
            : "\(placement.tier.name) starts at \(metric(floor ?? 0, method: result.method)), so this is \(placement.tier.name)"
        if let next = placement.tier.next, let threshold = placement.nextThreshold {
            tierLine += ", \(Format.percent(placement.progress)) of the way to \(next.name) at \(metric(threshold, method: result.method))."
        } else {
            tierLine += ", the top tier."
        }
        lines.append(tierLine)
        if result.usedCustomThresholds {
            lines.append("Using your own tier thresholds for this exercise.")
        } else if abs(scale - 1) > 0.001 {
            lines.append("Tiers are scaled to \(Format.percent(scale)) of PRIME's defaults (Profile → Rankings).")
        }
        return lines
    }
}
