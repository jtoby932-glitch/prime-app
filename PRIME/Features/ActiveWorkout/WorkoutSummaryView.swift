import SwiftData
import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @State private var appeared = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.accentSoft).frame(width: 96, height: 96)
                                .scaleEffect(appeared ? 1 : 0.6)
                            Circle().fill(Theme.accentGradient).frame(width: 68, height: 68)
                            Image(systemName: "checkmark").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        }
                        Text("Workout complete").eyebrow()
                        Text(summary.name).font(.primeLargeTitle).foregroundStyle(.white).multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        StatTile(value: Format.duration(summary.duration), label: "Duration", symbol: "clock.fill")
                        StatTile(value: Format.volume(summary.volumeKg, unit: unit, includeUnit: false), label: "Volume (\(unit.symbol))", symbol: "scalemass.fill", tint: Theme.info)
                        StatTile(value: "\(summary.setCount)", label: "Sets", symbol: "checkmark.circle.fill")
                        StatTile(value: "\(summary.exerciseCount)", label: "Exercises", symbol: "dumbbell.fill")
                    }

                    if !summary.rankChanges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Rank updates")
                            ForEach(Array(summary.rankChanges.enumerated()), id: \.element.id) { index, change in
                                HStack(spacing: 12) {
                                    TierBadgeView(tier: change.to, size: 40)
                                        .scaleEffect(appeared ? 1 : 0.3)
                                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(0.15 * Double(index) + 0.3), value: appeared)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        Text(change.from.map { "\($0.name) → \(change.to.name)" } ?? "First rank: \(change.to.name)")
                                            .font(.caption).foregroundStyle(change.to.color)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .primeCard(padding: 18)
                    }

                    if !summary.records.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: summary.records.count == 1 ? "New record" : "\(summary.records.count) new records")
                            ForEach(summary.records) { line in
                                HStack(spacing: 12) {
                                    IconBubble(symbol: line.achievement.kind.symbol, tint: Theme.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        Text(line.achievement.kind.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(line.achievement.valueText(unit: unit)).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                        if let gain = line.achievement.improvementText(unit: unit) {
                                            Text(gain).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                        }
                                    }
                                }
                            }
                        }
                        .primeCard(padding: 18)
                    } else {
                        Text("No new records this time. Consistency is what makes the next one happen.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button("Done") { dismiss() }
                        .buttonStyle(.primePrimary)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .primeBackground()
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
            }
        }
    }
}
