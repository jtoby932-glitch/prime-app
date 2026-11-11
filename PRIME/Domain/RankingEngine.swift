import Foundation

enum RankTier: Int, CaseIterable, Comparable, Identifiable, Codable {
    case beginner = 0, bronze, silver, gold, elite

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .beginner: return "Beginner"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .elite: return "Elite"
        }
    }

    var next: RankTier? { RankTier(rawValue: rawValue + 1) }

    static func < (lhs: RankTier, rhs: RankTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Tier for a continuous score in 0...5.
    static func forScore(_ score: Double) -> RankTier {
        RankTier(rawValue: min(4, max(0, Int(score.rounded(.down))))) ?? .beginner
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

/// Thresholds are the minimum metric for Bronze, Silver, Gold and Elite.
/// Anything under the Bronze threshold is Beginner.
struct RankingStandard: Equatable {
    var method: RankingMethod
    var thresholds: [Double]
    var isCustom: Bool
    var note: String

    static let version = 1
    static let sourceLabel = "Provisional PRIME tiers v\(version)"
    static let sourceDetail = "These tiers are PRIME's own starting points, not a validated population dataset. They aren't adjusted for sex, age or bodyweight class. Scale them in Settings or set your own per exercise."

    static func isValid(_ thresholds: [Double]) -> Bool {
        guard thresholds.count == 4, thresholds.allSatisfy({ $0.isFinite && $0 > 0 }) else { return false }
        return zip(thresholds, thresholds.dropFirst()).allSatisfy { $0 < $1 }
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
    /// 0...1 progress from this tier's floor to the next tier's floor. 1 at Elite.
    let progress: Double
    let nextThreshold: Double?
    /// Continuous score 0...5 (tier index + progress). Elite caps at 5.
    let score: Double
}

/// One logged set, with the bodyweight that applied on that day (if known).
struct RankableSet: Equatable {
    var weightKg: Double
    var reps: Int
    var date: Date
    var bodyweightKg: Double?
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
        precondition(thresholds.count == 4, "Expected four thresholds")
        let reached = thresholds.filter { metric >= $0 }.count
        let tier = RankTier(rawValue: reached) ?? .beginner
        if reached >= 4 {
            let gap = thresholds[3] - thresholds[2]
            let beyond = gap > 0 ? min(1, max(0, (metric - thresholds[3]) / gap)) : 0
            return RankPlacement(tier: .elite, progress: 1, nextThreshold: nil, score: min(5, 4 + beyond))
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

/// Averages exercise scores into an overall profile, keeping free weights and machines apart.
struct TrainingProfileSummary: Equatable {
    struct Group: Equatable {
        let score: Double
        let count: Int
        var tier: RankTier { RankTier.forScore(score) }
    }

    let overall: Group?
    let freeWeights: Group?
    let machines: Group?
    let tierCounts: [RankTier: Int]

    init(entries: [(score: Double, isFreeWeight: Bool)]) {
        func group(_ scores: [Double]) -> Group? {
            scores.isEmpty ? nil : Group(score: scores.reduce(0, +) / Double(scores.count), count: scores.count)
        }
        overall = group(entries.map(\.score))
        freeWeights = group(entries.filter(\.isFreeWeight).map(\.score))
        machines = group(entries.filter { !$0.isFreeWeight }.map(\.score))
        var counts: [RankTier: Int] = [:]
        for entry in entries { counts[RankTier.forScore(entry.score), default: 0] += 1 }
        tierCounts = counts
    }
}
