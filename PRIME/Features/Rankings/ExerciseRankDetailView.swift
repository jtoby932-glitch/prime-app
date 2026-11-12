import Charts
import SwiftData
import SwiftUI

struct ExerciseRankDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.motion) private var motion
    @Query private var profiles: [UserProfile]
    @Query(sort: \PerformanceRanking.recordedAt) private var allRankings: [PerformanceRanking]
    @Query private var allRecords: [PersonalRecord]
    @State private var showEditor = false
    @State private var appeared = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var scale: Double { profiles.first?.tierScale ?? 1 }

    var body: some View {
        let rank = RankingService.rank(for: exercise, history: store.history, submissions: allRankings, scale: scale)
        let history = allRankings.filter { $0.exerciseSlug == exercise.slug }
        let peakTier = history.map(\.tier).max() ?? rank.peak?.placement.tier
        let thresholds = exercise.rankingStandard.effectiveThresholds(scale: scale)
        let bodyweight = store.history.latestBodyweightKg

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(rank: rank, peakTier: peakTier)

                if exercise.isRanked {
                    Button { appState.rankEntry = RankEntryRequest(exerciseSlug: exercise.slug) } label: {
                        Label("Log a ranked performance", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.primePrimary)
                }

                if let result = rank.currentResult {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "How this was calculated")
                        ForEach(Array(RankFormat.explanation(result, unit: unit, scale: scale).enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textTertiary).frame(width: 16)
                                Text(line).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !exercise.rankingNote.isEmpty {
                            Label(exercise.rankingNote, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        if let target = RankFormat.targetText(NextTierTarget.make(for: result, increment: unit.toKilograms(unit.increment)), unit: unit) {
                            Label("Next: " + target, systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                        }
                    }
                    .primeCard(padding: 16)
                }

                if exercise.isRanked {
                    TierLadder(method: exercise.rankingMethod, thresholds: thresholds, current: rank.currentResult, bodyweightKg: bodyweight, unit: unit)
                }

                if history.count >= 2 {
                    RankHistoryChart(rankings: history, thresholds: thresholds, method: exercise.rankingMethod)
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Rank history", subtitle: "Every result is kept, never overwritten")
                        ForEach(history.reversed().prefix(12)) { entry in
                            RankHistoryRow(entry: entry, unit: unit)
                        }
                        if history.count > 12 {
                            Text("\(history.count - 12) earlier entries").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .primeCard(padding: 16)
                }

                bests

                BadgeGrid(title: "Badges", badges: BadgeEngine.exerciseBadges(
                    sessionCount: store.history.sessionCount(for: exercise.slug), peakTier: peakTier,
                    recordCount: allRecords.filter { $0.exerciseSlug == exercise.slug }.count,
                    isRanked: exercise.isRanked))

                VStack(alignment: .leading, spacing: 10) {
                    Label(exercise.rankingStandard.isCustom ? "Your own tiers" : RankingStandard.sourceLabel, systemImage: "info.circle")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    Text(exercise.rankingStandard.isCustom ? "You set these thresholds. Reset them to go back to PRIME's tiers." : RankingStandard.sourceDetail)
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 10) {
                        if exercise.rankingMethod != .unranked {
                            Button("Customise tiers") { showEditor = true }.buttonStyle(.prime(.secondary, compact: true))
                        }
                        NavigationLink(value: Route.methodology) {
                            Text("Methodology").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .primeBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { ThresholdEditorSheet(exercise: exercise) }
        .onAppear { withAnimation(motion.animation(.spring(response: 0.7, dampingFraction: 0.65))) { appeared = true } }
    }

    private func hero(rank: ExerciseRank, peakTier: RankTier?) -> some View {
        let result = rank.currentResult
        let tier = rank.currentTier
        return VStack(spacing: 12) {
            ZStack {
                Circle().fill(RadialGradient(colors: [tier.glow.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 120))
                    .frame(width: 240, height: 240)
                RankEmblem(tier: tier, size: 150, dimmed: result == nil, animated: true)
                    .scaleEffect(appeared || !motion.allowsMovement ? 1 : 0.7)
                    .opacity(appeared || !motion.allowsAnimation ? 1 : 0)
            }
            .frame(height: 200)
            Text(result == nil ? "Not ranked" : tier.name)
                .font(.system(size: 34, weight: .heavy).width(.expanded))
                .foregroundStyle(result == nil ? Theme.textSecondary : tier.color)
            if let result {
                Text(RankFormat.metric(result.metric, method: result.method)
                     + (result.estimatedOneRepMaxKg.map { " · \(result.set.isTestedMax ? "tested" : "est.") 1RM \(Format.estimate($0, unit: unit))" } ?? ""))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if let next = tier.next {
                    VStack(spacing: 6) {
                        ProgressBar(progress: result.placement.progress, tint: AnyShapeStyle(tier.gradient), height: 8)
                        HStack {
                            Text(tier.name).font(.caption.weight(.semibold)).foregroundStyle(tier.color)
                            Spacer()
                            Text("\(Format.percent(result.placement.progress))").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(next.name).font(.caption.weight(.semibold)).foregroundStyle(next.color)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            } else if let failure = rank.failure {
                Text(failure.message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            if let peakTier, peakTier > tier {
                Tag(text: "Peak: \(peakTier.name)", color: peakTier.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var bests: some View {
        let records = store.history.records(for: exercise.slug)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Personal bests")
            if !records.hasHistory {
                Text("Log this exercise in a workout to see your bests.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if let value = records.bestOneRepMaxKg { MetricRow(label: "Best estimated 1RM", value: Format.estimate(value, unit: unit)) }
            if let value = records.heaviestWeightKg { MetricRow(label: RecordKind.heaviestWeight.displayName, value: Format.weight(value, unit: unit)) }
            if let value = records.bestSetVolume { MetricRow(label: RecordKind.bestSetVolume.displayName, value: Format.volume(value, unit: unit)) }
            if let value = records.bestSessionVolume { MetricRow(label: RecordKind.bestSessionVolume.displayName, value: Format.volume(value, unit: unit)) }
            if records.heaviestWeightKg == nil, let reps = records.mostRepsByWeight[0] {
                MetricRow(label: "Most bodyweight reps", value: "\(reps)")
            }
        }
        .primeCard(padding: 16)
    }
}

struct TierLadder: View {
    let method: RankingMethod
    let thresholds: [Double]
    let current: RankResult?
    let bodyweightKg: Double?
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tier ladder", subtitle: method.metricName)
            ForEach(RankTier.allCases.reversed()) { tier in
                let isCurrent = (current?.placement.tier ?? .unranked) == tier && current != nil
                let reached = (current?.placement.tier ?? .unranked) >= tier
                HStack(spacing: 12) {
                    RankEmblem(tier: tier, size: 32, dimmed: !reached)
                    Text(tier.name).font(.subheadline.weight(isCurrent ? .bold : .medium)).foregroundStyle(isCurrent ? tier.color : Theme.textPrimary)
                    if isCurrent { Tag(text: "You", color: tier == .unranked ? Theme.accent : tier.color, filled: true) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(requirement(for: tier)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                        if method == .relativeLoad, tier != .unranked, let bodyweightKg, thresholds.count == RankTier.thresholdCount {
                            Text("≈ \(Format.estimate(thresholds[tier.rawValue - 1] * bodyweightKg, unit: unit, decimals: 0)) 1RM")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? tier.color.opacity(0.1) : .clear))
                .accessibilityElement(children: .combine)
            }
            if method == .relativeLoad {
                Text(bodyweightKg == nil ? "Ratios are estimated 1RM ÷ bodyweight." : "Ratios are estimated 1RM ÷ bodyweight; weights use your latest bodyweight.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .primeCard(padding: 16)
    }

    private func requirement(for tier: RankTier) -> String {
        guard thresholds.count == RankTier.thresholdCount else { return "–" }
        if tier == .unranked { return "under " + RankFormat.metric(thresholds[0], method: method) }
        return RankFormat.metric(thresholds[tier.rawValue - 1], method: method) + "+"
    }
}

struct RankHistoryChart: View {
    let rankings: [PerformanceRanking]
    let thresholds: [Double]
    let method: RankingMethod
    @State private var selected: Date?

    var body: some View {
        let shown = rankings.filter { $0.method == method }
        let top = max(shown.map(\.metric).max() ?? 1, thresholds.dropLast(2).last ?? 1) * 1.1
        let visibleThresholds = Array(thresholds.enumerated()).filter { $0.element <= top }
        let point = selected.flatMap { date in shown.min { abs($0.recordedAt.timeIntervalSince(date)) < abs($1.recordedAt.timeIntervalSince(date)) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Rank progression")
                if let point {
                    Text("\(point.recordedAt.relativeDayText): \(point.tier.name)")
                        .font(.caption.weight(.semibold)).foregroundStyle(point.tier.color)
                }
            }
            Chart {
                ForEach(visibleThresholds, id: \.offset) { index, value in
                    let tier = RankTier(rawValue: index + 1) ?? .bronze
                    RuleMark(y: .value("Tier", value))
                        .foregroundStyle(tier.color.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(tier.name).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                }
                ForEach(shown) { ranking in
                    LineMark(x: .value("Date", ranking.recordedAt), y: .value("Metric", ranking.metric))
                        .foregroundStyle(Theme.accentHighlight)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", ranking.recordedAt), y: .value("Metric", ranking.metric))
                        .foregroundStyle(ranking.tier.color)
                        .symbolSize(point?.id == ranking.id ? 80 : 30)
                }
                if let point {
                    RuleMark(x: .value("Selected", point.recordedAt)).foregroundStyle(Theme.borderStrong)
                }
            }
            .chartYScale(domain: 0...top)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 200)
            Text("Each point is one result, coloured by the tier it reached. Dashed lines are today's thresholds.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 16)
    }
}

struct BadgeGrid: View {
    let title: String
    let badges: [Badge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title)
                Text("\(badges.filter(\.isEarned).count)/\(badges.count)").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(badges) { badge in
                    VStack(spacing: 8) {
                        ZStack {
                            if let tier = badge.tier {
                                RankEmblem(tier: tier, size: 46, dimmed: !badge.isEarned)
                            } else {
                                Circle()
                                    .fill(badge.isEarned ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.field))
                                    .frame(width: 44, height: 44)
                                Image(systemName: badge.symbol)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(badge.isEarned ? Theme.onAccent : Theme.textTertiary)
                            }
                        }
                        .frame(height: 48)
                        Text(badge.title).font(.caption.weight(.bold)).foregroundStyle(badge.isEarned ? Theme.textPrimary : Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                        if badge.isEarned {
                            Text("Earned").font(.caption2).foregroundStyle(Theme.success)
                        } else {
                            ProgressBar(progress: badge.progress, height: 3).padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.title): \(badge.detail). \(badge.isEarned ? "Earned" : "\(Format.percent(badge.progress)) complete")")
                }
            }
        }
        .primeCard(padding: 16)
    }
}
