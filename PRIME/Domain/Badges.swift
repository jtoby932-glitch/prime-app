import Foundation

struct Badge: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Colours the badge like a rank tier when set.
    let tier: RankTier?
    let isEarned: Bool
    /// 0...1 progress for locked badges.
    let progress: Double
}

/// Badges are always derived from real logged data, never stored or faked.
enum BadgeEngine {
    static func exerciseBadges(samples: [SetSample], peakTier: RankTier?, recordCount: Int, isRanked: Bool, unit: WeightUnit) -> [Badge] {
        let sessions = Set(samples.map(\.sessionID)).count
        let volume = Analytics.totalVolume(samples)
        var badges: [Badge] = [
            Badge(id: "first", title: "First rep", detail: "Log this exercise once", symbol: "flag.checkered",
                  tier: nil, isEarned: !samples.isEmpty, progress: samples.isEmpty ? 0 : 1),
            counted(id: "regular", title: "Regular", detail: "Train it in 10 sessions", symbol: "calendar",
                    value: Double(sessions), target: 10),
            counted(id: "fifty", title: "Fifty sets", detail: "Complete 50 working sets", symbol: "square.stack.3d.up.fill",
                    value: Double(samples.count), target: 50),
            counted(id: "records", title: "Record breaker", detail: "Set 5 personal records", symbol: "trophy.fill",
                    value: Double(recordCount), target: 5),
        ]
        let tonne = 10_000.0
        if volume > 0 || samples.contains(where: { $0.weightKg > 0 }) {
            badges.append(counted(id: "volume", title: "Heavy lifting",
                                  detail: "Lift \(Format.volume(tonne, unit: unit)) in total", symbol: "scalemass.fill",
                                  value: volume, target: tonne))
        }
        if isRanked {
            for tier in RankTier.allCases where tier != .beginner {
                let earned = (peakTier ?? .beginner) >= tier
                badges.append(Badge(id: "tier-\(tier.rawValue)", title: tier.name, detail: "Reach \(tier.name) on this lift",
                                    symbol: "shield.lefthalf.filled", tier: tier, isEarned: earned, progress: earned ? 1 : 0))
            }
        }
        return badges
    }

    static func globalBadges(history: TrainingHistory, bestStreak: Int, recordCount: Int, peakTier: RankTier?, unit: WeightUnit) -> [Badge] {
        let workouts = Double(history.sessions.count)
        let volume = Analytics.totalVolume(history.samples)
        let tonne = 1000.0
        return [
            counted(id: "w1", title: "Day one", detail: "Finish your first workout", symbol: "figure.strengthtraining.traditional", value: workouts, target: 1),
            counted(id: "w10", title: "Ten down", detail: "Finish 10 workouts", symbol: "10.circle.fill", value: workouts, target: 10),
            counted(id: "w50", title: "Fifty strong", detail: "Finish 50 workouts", symbol: "50.circle.fill", value: workouts, target: 50),
            counted(id: "w100", title: "Centurion", detail: "Finish 100 workouts", symbol: "star.circle.fill", value: workouts, target: 100),
            counted(id: "s4", title: "Four-week run", detail: "Hit your weekly goal 4 weeks running", symbol: "flame.fill", value: Double(bestStreak), target: 4),
            counted(id: "s12", title: "Quarter of grit", detail: "Hit your weekly goal 12 weeks running", symbol: "flame.circle.fill", value: Double(bestStreak), target: 12),
            counted(id: "v100", title: "100 tonnes", detail: "Move \(Format.volume(100 * tonne, unit: unit)) in total", symbol: "shippingbox.fill", value: volume, target: 100 * tonne),
            counted(id: "v1000", title: "Thousand tonnes", detail: "Move \(Format.volume(1000 * tonne, unit: unit)) in total", symbol: "building.columns.fill", value: volume, target: 1000 * tonne),
            counted(id: "pr10", title: "Record setter", detail: "Set 10 personal records", symbol: "trophy.fill", value: Double(recordCount), target: 10),
            Badge(id: "gold", title: "Gold standard", detail: "Reach Gold on any lift", symbol: "shield.lefthalf.filled", tier: .gold,
                  isEarned: (peakTier ?? .beginner) >= .gold, progress: (peakTier ?? .beginner) >= .gold ? 1 : 0),
            Badge(id: "elite", title: "Elite", detail: "Reach Elite on any lift", symbol: "crown.fill", tier: .elite,
                  isEarned: (peakTier ?? .beginner) >= .elite, progress: (peakTier ?? .beginner) >= .elite ? 1 : 0),
        ]
    }

    private static func counted(id: String, title: String, detail: String, symbol: String, value: Double, target: Double) -> Badge {
        let progress = target > 0 ? min(1, max(0, value / target)) : 0
        return Badge(id: id, title: title, detail: detail, symbol: symbol, tier: nil, isEarned: value >= target, progress: progress)
    }
}
