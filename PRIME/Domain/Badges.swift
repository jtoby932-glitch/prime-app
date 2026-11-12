import Foundation

struct Badge: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Shown as a rank emblem when set.
    let tier: RankTier?
    let isEarned: Bool
    /// 0...1 progress for locked badges.
    let progress: Double
}

/// Achievements are always derived from logged data, never stored or faked. They reward
/// milestones and consistency, never sheer volume.
enum BadgeEngine {
    static func exerciseBadges(sessionCount: Int, peakTier: RankTier?, recordCount: Int, isRanked: Bool) -> [Badge] {
        var badges: [Badge] = [
            counted(id: "first", title: "First log", detail: "Record this exercise once", symbol: "flag.checkered", value: Double(sessionCount), target: 1),
            counted(id: "regular", title: "Regular", detail: "Train it in 10 workouts", symbol: "calendar", value: Double(sessionCount), target: 10),
            counted(id: "staple", title: "Staple", detail: "Train it in 25 workouts", symbol: "calendar.badge.checkmark", value: Double(sessionCount), target: 25),
            counted(id: "records", title: "Record breaker", detail: "Set 5 personal records on it", symbol: "trophy.fill", value: Double(recordCount), target: 5),
        ]
        if isRanked {
            for tier in RankTier.ranked {
                let earned = (peakTier ?? .unranked) >= tier
                badges.append(Badge(id: "tier-\(tier.rawValue)", title: tier.name, detail: "Reach \(tier.name) on this lift",
                                    symbol: "shield", tier: tier, isEarned: earned, progress: earned ? 1 : 0))
            }
        }
        return badges
    }

    static func globalBadges(workouts: Int, routineWorkouts: Int, bestStreak: Int, recordCount: Int, peakTier: RankTier?) -> [Badge] {
        let peak = peakTier ?? .unranked
        func rank(_ tier: RankTier, _ title: String) -> Badge {
            Badge(id: "rank-\(tier.rawValue)", title: title, detail: "Reach \(tier.name) on any lift", symbol: "shield",
                  tier: tier, isEarned: peak >= tier, progress: peak >= tier ? 1 : 0)
        }
        return [
            counted(id: "w1", title: "Day one", detail: "Finish your first workout", symbol: "figure.strengthtraining.traditional", value: Double(workouts), target: 1),
            counted(id: "routine1", title: "To the plan", detail: "Finish a workout from one of your routines", symbol: "checklist", value: Double(routineWorkouts), target: 1),
            counted(id: "pr1", title: "First record", detail: "Beat a previous best", symbol: "trophy.fill", value: Double(recordCount), target: 1),
            counted(id: "w10", title: "Ten down", detail: "Finish 10 workouts", symbol: "10.circle.fill", value: Double(workouts), target: 10),
            counted(id: "w50", title: "Fifty strong", detail: "Finish 50 workouts", symbol: "50.circle.fill", value: Double(workouts), target: 50),
            counted(id: "w100", title: "Centurion", detail: "Finish 100 workouts", symbol: "star.circle.fill", value: Double(workouts), target: 100),
            counted(id: "s4", title: "Four-week run", detail: "Meet your weekly goal 4 weeks running", symbol: "flame.fill", value: Double(bestStreak), target: 4),
            counted(id: "s12", title: "Quarter of grit", detail: "Meet your weekly goal 12 weeks running", symbol: "flame.circle.fill", value: Double(bestStreak), target: 12),
            counted(id: "s26", title: "Half a year", detail: "Meet your weekly goal 26 weeks running", symbol: "medal.fill", value: Double(bestStreak), target: 26),
            counted(id: "pr10", title: "Record setter", detail: "Set 10 personal records", symbol: "rosette", value: Double(recordCount), target: 10),
            rank(.bronze, "On the ladder"),
            rank(.gold, "Gold standard"),
            rank(.diamond, "Diamond"),
            rank(.master, "Master"),
        ]
    }

    private static func counted(id: String, title: String, detail: String, symbol: String, value: Double, target: Double) -> Badge {
        let progress = target > 0 ? min(1, max(0, value / target)) : 0
        return Badge(id: id, title: title, detail: detail, symbol: symbol, tier: nil, isEarned: value >= target, progress: progress)
    }
}
