import SwiftData
import SwiftUI

/// Plain explanation of how PRIME ranks lifts, so the system can be trusted.
struct RankingMethodologyView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        let ranked = exercises.filter(\.isRanked)
        let load = ranked.filter { $0.rankingMethod == .relativeLoad }
        let reps = ranked.filter { $0.rankingMethod == .repetitions }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(RankTier.allCases) { RankEmblem(tier: $0, size: 38) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                block("The ladder", symbol: "stairs") {
                    para("Every ranked exercise has its own ladder: Unranked, Bronze, Silver, Gold, Platinum, Diamond, Elite and Master. Each exercise has its own seven thresholds, because a good squat and a good curl are very different numbers.")
                    para("There's deliberately no single overall rank. Averaging unrelated lifts into one number would be misleading, so PRIME shows how many of your lifts sit at each tier instead.")
                    para("These tiers are PRIME's own progression system. They are not an official or population-based strength standard, and they aren't adjusted for sex, age or bodyweight class. You can scale them all in Profile → Rankings, or set your own for any exercise.")
                }

                block("Loaded exercises", symbol: "scalemass") {
                    para("For barbell, dumbbell, cable and machine lifts PRIME estimates your one-rep max with the Epley formula:")
                    formula("Estimated 1RM = weight × (1 + reps ÷ 30)")
                    para("A single rep counts as a tested 1RM, so it isn't inflated. Everything else is labelled as an estimate. Sets over \(StrengthMath.reliableRepLimit) reps aren't ranked because the estimate becomes unreliable.")
                    para("The estimate is divided by your bodyweight, using the entry logged nearest to that workout:")
                    formula("Relative strength = estimated 1RM ÷ bodyweight")
                    para("If no bodyweight is recorded, loaded lifts can't be ranked. PRIME tells you rather than guessing.")
                    para("Dumbbell tiers use the weight of one dumbbell. Barbell tiers use the total weight including the bar.")
                }

                block("Bodyweight exercises", symbol: "figure.core.training") {
                    para("Pull-ups, dips, push-ups and similar rank on the most reps in one set. Bodyweight isn't needed for these.")
                    para("If you add weight, the set is converted into bodyweight-equivalent reps with the same Epley formula, so a weighted set is credited fairly:")
                    formula("Equivalent reps = 30 × ((bodyweight + added) × (1 + reps ÷ 30) ÷ bodyweight − 1)")
                }

                block("Machines and equipment", symbol: "gearshape.2") {
                    para("Each equipment variation is its own exercise with its own ladder. A machine chest press is never compared with a barbell bench press.")
                    para("Machine and cable loads also vary between manufacturers, so their tiers are only comparable on similar equipment. Resistance band and rotational exercises aren't ranked because their load can't be measured consistently.")
                }

                block("What counts", symbol: "checkmark.seal") {
                    para("Your current rank is your best rankable set from the last \(RankingService.currentWindowDays) days, from workouts or performances you log on the Rankings tab. Your peak rank is your best ever.")
                    para("Inputs are validated before anything is ranked: zero reps, impossible weights and unsupported combinations are rejected.")
                    para("You never need to attempt a maximal lift. A normal working set of a few reps gives a fair estimate, and steady progress is what moves you up.")
                }

                block("Editing and history", symbol: "clock.arrow.circlepath") {
                    para("Rank history is never overwritten when you improve; each result is kept with its date and performance.")
                    para("If you edit or delete a workout, or change tier thresholds, the rank entries that came from workouts are recalculated so they stay consistent with your data. Performances you logged directly keep the rank they earned at the time.")
                }

                block("Supported exercises", symbol: "list.bullet") {
                    para("\(load.count) loaded exercises and \(reps.count) bodyweight exercises are ranked.")
                    Text(ranked.map(\.name).joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .primeBackground()
        .navigationTitle("How ranking works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.primeTitle3).foregroundStyle(Theme.textPrimary)
            content()
        }
        .primeCard(padding: 16)
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
    }

    private func formula(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .foregroundStyle(Theme.accentHighlight)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft))
    }
}

/// Every rank result across all lifts, newest first. Logged performances can be removed here.
struct RankHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PerformanceRanking.recordedAt, order: .reverse) private var rankings: [PerformanceRanking]
    @Query private var profiles: [UserProfile]

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        List {
            if rankings.isEmpty {
                Text("No ranked results yet.").foregroundStyle(Theme.textSecondary).listRowBackground(Theme.card)
            }
            ForEach(rankings) { entry in
                NavigationLink(value: Route.exerciseRank(entry.exerciseSlug)) { RankHistoryRow(entry: entry, unit: unit) }
                    .listRowBackground(Theme.card)
                    .deleteDisabled(!entry.isSubmitted)
            }
            .onDelete { offsets in
                for index in offsets where rankings[index].isSubmitted { context.delete(rankings[index]) }
                try? context.save()
            }
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .navigationTitle("Rank history")
        .safeAreaInset(edge: .bottom) {
            Text("Swipe to remove a performance you logged. Results from workouts follow the workout itself.")
                .font(.caption).foregroundStyle(Theme.textTertiary).padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        }
    }
}
