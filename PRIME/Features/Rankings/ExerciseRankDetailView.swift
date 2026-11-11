import Charts
import SwiftData
import SwiftUI

struct ExerciseRankDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \PerformanceRanking.recordedAt) private var allRankings: [PerformanceRanking]
    @Query private var allRecords: [PersonalRecord]
    @State private var showEditor = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var scale: Double { profiles.first?.tierScale ?? 1 }

    var body: some View {
        let rank = RankingService.rank(for: exercise, history: store.history, scale: scale)
        let history = allRankings.filter { $0.exerciseSlug == exercise.slug }
        let peakTier = history.map(\.tier).max() ?? rank.peak?.placement.tier
        let thresholds = exercise.rankingStandard.effectiveThresholds(scale: scale)
        let bodyweight = store.history.latestBodyweightKg

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(rank: rank, peakTier: peakTier)

                if let result = rank.currentResult {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "How this was calculated")
                        ForEach(Array(RankFormat.explanation(result, unit: unit, scale: scale, note: exercise.rankingNote).enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.heavy)).foregroundStyle(Theme.textTertiary).frame(width: 16)
                                Text(line).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .primeCard(padding: 18)
                }

                if exercise.isRanked {
                    TierLadder(method: exercise.rankingMethod, thresholds: thresholds, current: rank.currentResult, bodyweightKg: bodyweight, unit: unit)
                }

                if history.count >= 2 {
                    RankHistoryChart(rankings: history, thresholds: thresholds, method: exercise.rankingMethod)
                }

                bests

                BadgeGrid(title: "Badges", badges: BadgeEngine.exerciseBadges(
                    samples: store.history.samples(for: exercise.slug), peakTier: peakTier,
                    recordCount: allRecords.filter { $0.exerciseSlug == exercise.slug }.count,
                    isRanked: exercise.isRanked, unit: unit))

                VStack(alignment: .leading, spacing: 10) {
                    Label(exercise.rankingStandard.isCustom ? "Your own tiers" : RankingStandard.sourceLabel, systemImage: "info.circle")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    Text(exercise.rankingStandard.isCustom ? "You set these thresholds. Reset them to go back to PRIME's provisional tiers." : RankingStandard.sourceDetail)
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                    if exercise.rankingMethod != .unranked {
                        Button("Customise tiers") { showEditor = true }.buttonStyle(.prime(.secondary, compact: true))
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { ThresholdEditorSheet(exercise: exercise) }
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.6)) { appeared = true } }
    }

    private func hero(rank: ExerciseRank, peakTier: RankTier?) -> some View {
        let result = rank.currentResult
        let tier = result?.placement.tier ?? .beginner
        return VStack(spacing: 14) {
            TierBadgeView(tier: tier, size: 120, dimmed: result == nil)
                .scaleEffect(appeared ? 1 : 0.7)
                .rotation3DEffect(.degrees(appeared ? 0 : -40), axis: (x: 0, y: 1, z: 0))
            Text(result == nil ? "Not ranked" : tier.name)
                .font(.primeLargeTitle)
                .foregroundStyle(result == nil ? Theme.textSecondary : tier.color)
            if let result {
                Text(RankFormat.metric(result.metric, method: result.method) + (result.estimatedOneRepMaxKg.map { " · e1RM \(Format.weight($0, unit: unit))" } ?? ""))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                if let next = tier.next {
                    VStack(spacing: 6) {
                        ProgressBar(progress: result.placement.progress, tint: AnyShapeStyle(tier.gradient), height: 8)
                        Text("\(Format.percent(result.placement.progress)) of the way to \(next.name)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 30)
                }
            } else if let failure = rank.failure {
                Text(failure.message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            if let peakTier, peakTier > (result?.placement.tier ?? .beginner) {
                Tag(text: "Peak: \(peakTier.name)", color: peakTier.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var bests: some View {
        let records = store.history.records(for: exercise.slug)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Personal bests")
            if !records.hasHistory {
                Text("Log this exercise to see your bests.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if let value = records.bestOneRepMaxKg { bestRow(RecordKind.bestOneRepMax, Format.weight(value, unit: unit)) }
            if let value = records.heaviestWeightKg { bestRow(RecordKind.heaviestWeight, Format.weight(value, unit: unit)) }
            if let value = records.bestSetVolume { bestRow(RecordKind.bestSetVolume, Format.volume(value, unit: unit)) }
            if let value = records.bestSessionVolume { bestRow(RecordKind.bestSessionVolume, Format.volume(value, unit: unit)) }
            if records.heaviestWeightKg == nil, let reps = records.mostRepsByWeight[0] {
                bestRow(RecordKind.mostRepsAtWeight, "\(reps) reps")
            }
        }
        .primeCard(padding: 18)
    }

    private func bestRow(_ kind: RecordKind, _ value: String) -> some View {
        HStack {
            Label(kind.displayName, systemImage: kind.symbol).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
        }
    }
}

struct TierLadder: View {
    let method: RankingMethod
    let thresholds: [Double]
    let current: RankResult?
    let bodyweightKg: Double?
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tier ladder")
            ForEach(RankTier.allCases.reversed()) { tier in
                let isCurrent = current?.placement.tier == tier
                HStack(spacing: 12) {
                    TierBadgeView(tier: tier, size: 28, dimmed: !isCurrent && (current?.placement.tier ?? .beginner) < tier)
                    Text(tier.name).font(.subheadline.weight(isCurrent ? .bold : .medium)).foregroundStyle(isCurrent ? tier.color : .white)
                    if isCurrent { Tag(text: "You", color: tier.color, filled: true) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(requirement(for: tier)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                        if method == .relativeLoad, tier != .beginner, let bodyweightKg, thresholds.count == 4 {
                            Text("≈ \(Format.weight(thresholds[tier.rawValue - 1] * bodyweightKg, unit: unit)) 1RM")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? tier.color.opacity(0.1) : .clear))
            }
            if method == .relativeLoad {
                Text(bodyweightKg == nil ? "Ratios are estimated 1RM ÷ bodyweight." : "Ratios are estimated 1RM ÷ bodyweight; weights shown use your latest bodyweight.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .primeCard(padding: 18)
    }

    private func requirement(for tier: RankTier) -> String {
        guard thresholds.count == 4 else { return "–" }
        if tier == .beginner { return "under " + RankFormat.metric(thresholds[0], method: method) }
        return RankFormat.metric(thresholds[tier.rawValue - 1], method: method) + "+"
    }
}

struct RankHistoryChart: View {
    let rankings: [PerformanceRanking]
    let thresholds: [Double]
    let method: RankingMethod
    @State private var selected: Date?

    var body: some View {
        let top = max(rankings.map(\.metric).max() ?? 1, thresholds.last ?? 1) * 1.08
        let point = selected.flatMap { date in rankings.min { abs($0.recordedAt.timeIntervalSince(date)) < abs($1.recordedAt.timeIntervalSince(date)) } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Rank history")
                if let point {
                    Text("\(point.recordedAt.relativeDayText): \(RankFormat.metric(point.metric, method: method))")
                        .font(.caption.weight(.semibold)).foregroundStyle(point.tier.color)
                }
            }
            Chart {
                ForEach(Array(thresholds.enumerated()), id: \.offset) { index, value in
                    RuleMark(y: .value("Tier", value))
                        .foregroundStyle((RankTier(rawValue: index + 1) ?? .bronze).color.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text((RankTier(rawValue: index + 1) ?? .bronze).name).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                }
                ForEach(rankings) { ranking in
                    LineMark(x: .value("Date", ranking.recordedAt), y: .value("Metric", ranking.metric))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", ranking.recordedAt), y: .value("Metric", ranking.metric))
                        .foregroundStyle(ranking.tier.color)
                        .symbolSize(30)
                }
                if let point {
                    RuleMark(x: .value("Selected", point.recordedAt)).foregroundStyle(Theme.strokeStrong)
                }
            }
            .chartYScale(domain: 0...top)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 200)
            Text(method == .relativeLoad ? "Best estimated 1RM ÷ bodyweight per workout. Dashed lines are the current tier thresholds." : "Best reps per workout. Dashed lines are the current tier thresholds.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 18)
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
                                TierBadgeView(tier: tier, size: 40, dimmed: !badge.isEarned)
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
                        Text(badge.title).font(.caption.weight(.bold)).foregroundStyle(badge.isEarned ? .white : Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                        if badge.isEarned {
                            Text("Earned").font(.caption2).foregroundStyle(Theme.accent)
                        } else {
                            ProgressBar(progress: badge.progress, height: 3).padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.title): \(badge.detail). \(badge.isEarned ? "Earned" : "\(Format.percent(badge.progress)) complete")")
                }
            }
        }
        .primeCard(padding: 18)
    }
}
