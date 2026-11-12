import SwiftData
import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    @Environment(\.bodyModel) private var model
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var appeared = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1).frame(width: 112, height: 112)
                                .scaleEffect(appeared || !motion.allowsMovement ? 1 : 0.5)
                            Circle().fill(Theme.accentSoft).frame(width: 92, height: 92)
                            Circle().fill(Theme.accentGradient).frame(width: 66, height: 66)
                                .shadow(color: Theme.accent.opacity(0.6), radius: 18)
                            Image(systemName: "checkmark").font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.onAccent)
                                .scaleEffect(appeared || !motion.allowsMovement ? 1 : 0.2)
                        }
                        Text("Workout complete").eyebrow(Theme.accentHighlight)
                        Text(summary.name).font(.primeLargeTitle).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        StatTile(value: Format.duration(summary.duration), label: "Duration", symbol: "clock.fill")
                        StatTile(count: summary.exerciseCount, label: "Exercises", symbol: "dumbbell.fill")
                        StatTile(count: summary.setCount, label: "Sets", symbol: "checkmark.circle.fill")
                        StatTile(count: summary.repCount, label: "Reps", symbol: "repeat")
                        StatTile(value: Format.volume(summary.volumeKg, unit: unit, includeUnit: false), label: "Volume \(unit.symbol)", symbol: "scalemass.fill",
                                 numeric: unit.fromKilograms(summary.volumeKg), format: { Format.number($0.rounded(), maxFractionDigits: 0) })
                        StatTile(count: summary.records.count, label: "Records", symbol: "trophy.fill", tint: Theme.warning)
                    }

                    if !summary.rankChanges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Rank updates")
                            ForEach(Array(summary.rankChanges.enumerated()), id: \.element.id) { index, change in
                                HStack(spacing: 12) {
                                    RankEmblem(tier: change.to, size: 46)
                                        .scaleEffect(appeared || !motion.allowsMovement ? 1 : 0.3)
                                        .animation(motion.animation(.spring(response: 0.5, dampingFraction: 0.6)).map { $0.delay(0.15 * Double(index) + 0.3) }, value: appeared)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(change.from.map { "\($0.name) → \(change.to.name)" } ?? "First rank: \(change.to.name)")
                                            .font(.caption).foregroundStyle(change.to.color)
                                    }
                                    Spacer()
                                    Button("Reveal") { showReveal(change) }
                                        .buttonStyle(.prime(.quiet, compact: true))
                                }
                            }
                        }
                        .primeCard(padding: 16)
                    }

                    if !summary.records.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: summary.records.count == 1 ? "New record" : "\(summary.records.count) new records")
                            ForEach(summary.records) { line in
                                HStack(spacing: 12) {
                                    IconBubble(symbol: line.achievement.kind.symbol, tint: Theme.warning, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(line.achievement.kind.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(line.achievement.valueText(unit: unit)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                                        if let gain = line.achievement.improvementText(unit: unit) {
                                            Text(gain).font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
                                        }
                                    }
                                }
                            }
                        }
                        .primeCard(padding: 16)
                    }

                    if !summary.muscles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Muscles trained", subtitle: summary.muscles.map(\.displayName).joined(separator: ", "))
                            HStack(spacing: 8) {
                                AnatomyCanvas(side: .front, primary: summary.muscles, model: model).frame(height: 190)
                                AnatomyCanvas(side: .back, primary: summary.muscles, model: model).frame(height: 190)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .primeCard(padding: 16)
                    }

                    if summary.records.isEmpty && summary.rankChanges.isEmpty {
                        Text("No new records this time. Showing up consistently is what makes the next one possible.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button("Done") { dismiss() }.buttonStyle(.primePrimary)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .primeBackground()
            .onAppear {
                withAnimation(motion.animation(.spring(response: 0.6, dampingFraction: 0.65))) { appeared = true }
            }
        }
    }

    private func showReveal(_ change: RankChange) {
        let equipment = exercises.first { $0.slug == change.exerciseSlug }?.equipment ?? .barbell
        let isBest = summary.records.contains { $0.exerciseSlug == change.exerciseSlug && ($0.achievement.kind == .bestOneRepMax || $0.achievement.kind == .mostRepsAtWeight) }
        let reveal = RankReveal(exerciseName: change.exerciseName, exerciseSlug: change.exerciseSlug, equipment: equipment,
                                result: change.result, previousTier: change.from, previousBestMetric: nil, isPersonalBest: isBest,
                                next: NextTierTarget.make(for: change.result, increment: unit.toKilograms(unit.increment)), unit: unit)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { appState.reveal = reveal }
    }
}
