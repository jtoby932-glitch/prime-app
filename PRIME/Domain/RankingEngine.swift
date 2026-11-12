import Foundation

/// PRIME's own progression ladder. Each exercise has its own thresholds for every tier.
enum RankTier: Int, CaseIterable, Comparable, Identifiable, Codable {
    case unranked = 0, bronze, silver, gold, platinum, diamond, elite, master

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .unranked: return "Unranked"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .diamond: return "Diamond"
        case .elite: return "Elite"
        case .master: return "Master"
        }
    }

    var next: RankTier? { RankTier(rawValue: rawValue + 1) }
    var previous: RankTier? { RankTier(rawValue: rawValue - 1) }

    /// Tiers that have a threshold (everything except Unranked).
    static var ranked: [RankTier] { allCases.filter { $0 != .unranked } }
    static let thresholdCount = 7

    static func < (lhs: RankTier, rhs: RankTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Tier for a continuous score in 0...8.
    static func forScore(_ score: Double) -> RankTier {
        RankTier(rawValue: min(7, max(0, Int(score.rounded(.down))))) ?? .unranked
    }
}

enum RankingMethod: String, CaseIterable, Codable {
    /// Estimated 1RM ÷ bodyweight. Used for loaded exercises.
    case relativeLoad = "load"
    /// Best set of reps (weighted sets converted to bodyweight-equivalent reps).
    case repetitions = "reps"
    /// Not ranked, e.g. carries or highly variable band work.
    case unranked = "none"

    var metricName: String {
        switch self {
        case .relativeLoad: return "Est. 1RM ÷ bodyweight"
        case .repetitions: return "Reps in one set"
        case .unranked: return "Not ranked"
        }
    }
}

/// Thresholds are the minimum metric for Bronze through Master (seven values).
/// Anything under the Bronze threshold is Unranked.
struct RankingStandard: Equatable {
    var method: RankingMethod
    var thresholds: [Double]
    var isCustom: Bool
    var note: String

    static let version = 2
    static let sourceLabel = "PRIME progression tiers v\(version)"
    static let sourceDetail = "These tiers are PRIME's own progression system, not an official or population-based strength standard. They aren't adjusted for sex, age or bodyweight class. Scale them in Profile or set your own per exercise."

    static func isValid(_ thresholds: [Double]) -> Bool {
        guard thresholds.count == RankTier.thresholdCount, thresholds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return false }
        return zip(thresholds, thresholds.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Seven evenly spaced thresholds from Bronze (`low`) to Master (`high`).
    static func ladder(low: Double, high: Double, wholeNumbers: Bool = false) -> [Double] {
        let step = (high - low) / Double(RankTier.thresholdCount - 1)
        var values = (0..<RankTier.thresholdCount).map { low + step * Double($0) }
        if wholeNumbers {
            values = values.map { $0.rounded() }
            for index in 1..<values.count where values[index] <= values[index - 1] { values[index] = values[index - 1] + 1 }
        }
        return values
    }

    /// Converts thresholds saved by PRIME 1.0 (Bronze, Silver, Gold, Elite) to the seven-tier ladder,
    /// keeping the four values the user chose and filling the new tiers in between and above.
    static func upgradeLegacy(_ old: [Double]) -> [Double]? {
        guard old.count == 4, zip(old, old.dropFirst()).allSatisfy({ $0 < $1 }), old[0] > 0 else { return nil }
        let (bronze, silver, gold, elite) = (old[0], old[1], old[2], old[3])
        let gap = elite - gold
        return [bronze, silver, gold, gold + gap / 3, gold + 2 * gap / 3, elite, elite + gap / 2]
    }

    /// Default thresholds multiplied by the user's tier scale. Custom thresholds are used as typed.
    func effectiveThresholds(scale: Double) -> [Double] {
        guard !isCustom else { return thresholds }
        let safeScale = (scale.isFinite && scale > 0) ? scale : 1
        return thresholds.map { $0 * safeScale }
    }
}

struct RankPlacement: Equatable {
    let tier: RankTier
    /// 0...1 progress from this tier's floor to the next tier's floor. 1 at Master.
    let progress: Double
    let nextThreshold: Double?
    /// Continuous score 0...8 (tier index + progress). Master caps at 8.
    let score: Double
}

/// One logged set, with the bodyweight that applied on that day (if known).
struct RankableSet: Equatable {
    var weightKg: Double
    var reps: Int
    var date: Date
    var bodyweightKg: Double?

    /// A single rep is a tested maximum; anything more is an estimate.
    var isTestedMax: Bool { reps == 1 }
}

enum RankingFailure: Error, Equatable {
    case unranked
    case invalidStandard
    case invalidSet
    case missingBodyweight
    case tooManyReps
    case noSets

    var message: String {
        switch self {
        case .unranked: return "This exercise isn't ranked."
        case .invalidStandard: return "The tier thresholds for this exercise aren't valid."
        case .invalidSet: return "Enter a weight and at least one rep."
        case .missingBodyweight: return "Add your bodyweight to rank this exercise."
        case .tooManyReps: return "Sets above \(StrengthMath.reliableRepLimit) reps are too unreliable to rank."
        case .noSets: return "Log a set of \(StrengthMath.reliableRepLimit) reps or fewer to get a rank."
        }
    }
}

struct RankResult: Equatable {
    let method: RankingMethod
    let set: RankableSet
    let estimatedOneRepMaxKg: Double?
    let relativeStrength: Double?
    /// The value compared against thresholds (ratio or reps).
    let metric: Double
    let thresholds: [Double]
    let placement: RankPlacement
    let usedCustomThresholds: Bool
}

enum RankingEngine {
    static func placement(metric: Double, thresholds: [Double]) -> RankPlacement {
        precondition(thresholds.count == RankTier.thresholdCount, "Expected seven thresholds")
        let top = RankTier.thresholdCount
        let reached = thresholds.filter { metric >= $0 }.count
        let tier = RankTier(rawValue: reached) ?? .unranked
        if reached >= top {
            let gap = thresholds[top - 1] - thresholds[top - 2]
            let beyond = gap > 0 ? min(1, max(0, (metric - thresholds[top - 1]) / gap)) : 0
            return RankPlacement(tier: .master, progress: 1, nextThreshold: nil, score: min(Double(top + 1), Double(top) + beyond))
        }
        let lower = reached == 0 ? 0 : thresholds[reached - 1]
        let upper = thresholds[reached]
        let span = upper - lower
        let progress = span > 0 ? min(1, max(0, (metric - lower) / span)) : 0
        return RankPlacement(tier: tier, progress: progress, nextThreshold: upper, score: Double(reached) + min(progress, 0.999))
    }

    /// Ranks a single set.
    static func evaluate(_ set: RankableSet, standard: RankingStandard, scale: Double = 1) -> Result<RankResult, RankingFailure> {
        guard standard.method != .unranked else { return .failure(.unranked) }
        let thresholds = standard.effectiveThresholds(scale: scale)
        guard RankingStandard.isValid(thresholds) else { return .failure(.invalidStandard) }
        guard set.reps > 0, set.weightKg.isFinite, set.weightKg >= 0 else { return .failure(.invalidSet) }

        switch standard.method {
        case .relativeLoad:
            guard set.weightKg > 0 else { return .failure(.invalidSet) }
            guard set.reps <= StrengthMath.reliableRepLimit else { return .failure(.tooManyReps) }
            guard let oneRepMax = StrengthMath.estimatedOneRepMax(weight: set.weightKg, reps: set.reps) else {
                return .failure(.invalidSet)
            }
            guard let ratio = StrengthMath.relativeStrength(oneRepMax: oneRepMax, bodyweight: set.bodyweightKg) else {
                return .failure(.missingBodyweight)
            }
            return .success(RankResult(
                method: .relativeLoad, set: set, estimatedOneRepMaxKg: oneRepMax, relativeStrength: ratio,
                metric: ratio, thresholds: thresholds, placement: placement(metric: ratio, thresholds: thresholds),
                usedCustomThresholds: standard.isCustom
            ))

        case .repetitions:
            if set.weightKg > 0 {
                if set.bodyweightKg == nil { return .failure(.missingBodyweight) }
                if set.reps > StrengthMath.reliableRepLimit { return .failure(.tooManyReps) }
            }
            guard let reps = StrengthMath.bodyweightEquivalentReps(bodyweight: set.bodyweightKg, addedWeight: set.weightKg, reps: set.reps) else {
                return .failure(.invalidSet)
            }
            return .success(RankResult(
                method: .repetitions, set: set, estimatedOneRepMaxKg: nil, relativeStrength: nil,
                metric: reps, thresholds: thresholds, placement: placement(metric: reps, thresholds: thresholds),
                usedCustomThresholds: standard.isCustom
            ))

        case .unranked:
            return .failure(.unranked)
        }
    }

    /// The best-ranked set among many. When none can be ranked, returns the most useful reason.
    static func best(of sets: [RankableSet], standard: RankingStandard, scale: Double = 1) -> Result<RankResult, RankingFailure> {
        guard standard.method != .unranked else { return .failure(.unranked) }
        guard !sets.isEmpty else { return .failure(.noSets) }
        var best: RankResult?
        var failures: [RankingFailure] = []
        for set in sets {
            switch evaluate(set, standard: standard, scale: scale) {
            case .success(let result):
                if best == nil || result.metric > best!.metric { best = result }
            case .failure(let failure):
                failures.append(failure)
            }
        }
        if let best { return .success(best) }
        for reason in [RankingFailure.invalidStandard, .missingBodyweight, .tooManyReps, .invalidSet] where failures.contains(reason) {
            return .failure(reason)
        }
        return .failure(.noSets)
    }
}

/// Counts of exercise ranks. PRIME deliberately has no single overall rank: unrelated lifts
/// can't be averaged into one meaningful number.
struct RankDistribution: Equatable {
    let tierCounts: [RankTier: Int]
    let highest: RankTier?
    let rankedCount: Int

    init(tiers: [RankTier]) {
        var counts: [RankTier: Int] = [:]
        for tier in tiers { counts[tier, default: 0] += 1 }
        tierCounts = counts
        highest = tiers.max()
        rankedCount = tiers.filter { $0 != .unranked }.count
    }
}

/// What it takes to reach the next tier, in terms the user can act on.
struct NextTierTarget: Equatable {
    let tier: RankTier
    /// Estimated 1RM needed (relative-load exercises).
    let oneRepMaxKg: Double?
    /// Weight needed at the same rep count, rounded up to a loadable increment.
    let weightKg: Double?
    let reps: Int
    /// Bodyweight-equivalent reps needed (rep-ranked exercises).
    let repsNeeded: Int?

    static func make(for result: RankResult, increment: Double) -> NextTierTarget? {
        guard let next = result.placement.tier.next, let threshold = result.placement.nextThreshold else { return nil }
        switch result.method {
        case .relativeLoad:
            guard let bodyweight = result.set.bodyweightKg, bodyweight > 0 else { return nil }
            let target = threshold * bodyweight
            let reps = max(1, min(result.set.reps, StrengthMath.reliableRepLimit))
            let raw = reps == 1 ? target : target / (1 + Double(reps) / 30)
            let step = increment > 0 ? increment : 2.5
            let weight = (raw / step).rounded(.up) * step
            return NextTierTarget(tier: next, oneRepMaxKg: target, weightKg: weight, reps: reps, repsNeeded: nil)
        case .repetitions:
            return NextTierTarget(tier: next, oneRepMaxKg: nil, weightKg: nil, reps: result.set.reps, repsNeeded: Int(threshold.rounded(.up)))
        case .unranked:
            return nil
        }
    }
}
