import Foundation
import SwiftData

struct ExerciseRank: Identifiable {
    let exercise: Exercise
    /// Best set in the current window (workouts and submitted performances).
    let current: Result<RankResult, RankingFailure>
    /// Best set ever.
    let peak: RankResult?

    var id: String { exercise.slug }
    var currentResult: RankResult? { if case .success(let result) = current { return result } else { return nil } }
    var failure: RankingFailure? { if case .failure(let failure) = current { return failure } else { return nil } }
    var currentTier: RankTier { currentResult?.placement.tier ?? .unranked }
}

/// Everything the rank reveal shows. Computed in full before the reveal starts.
struct RankReveal: Identifiable {
    let id = UUID()
    let exerciseName: String
    let exerciseSlug: String
    let equipment: Equipment
    let result: RankResult
    let previousTier: RankTier?
    let previousBestMetric: Double?
    let isPersonalBest: Bool
    let next: NextTierTarget?
    let unit: WeightUnit

    var tier: RankTier { result.placement.tier }
    var isRankUp: Bool { previousTier.map { tier > $0 } ?? (tier > .unranked) }
}

@MainActor
enum RankingService {
    static let currentWindowDays = 90

    static func submittedSets(for slug: String, in rankings: [PerformanceRanking]) -> [RankableSet] {
        rankings.filter { $0.exerciseSlug == slug && $0.isSubmitted }.map(\.rankableSet)
    }

    static func rank(for exercise: Exercise, history: TrainingHistory, submissions: [PerformanceRanking], scale: Double, now: Date = Date()) -> ExerciseRank {
        let fallback = history.latestBodyweightKg
        let all = history.rankableSets(for: exercise.slug, fallbackBodyweight: fallback) + submittedSets(for: exercise.slug, in: submissions)
        let since = Calendar.prime.date(byAdding: .day, value: -currentWindowDays, to: now) ?? now
        let recent = all.filter { $0.date >= since }
        let standard = exercise.rankingStandard
        let peakResult = try? RankingEngine.best(of: all, standard: standard, scale: scale).get()
        let current: Result<RankResult, RankingFailure>
        if !exercise.isRanked {
            current = .failure(.unranked)
        } else if recent.isEmpty && !all.isEmpty {
            current = .failure(.noSets)
        } else {
            current = RankingEngine.best(of: recent, standard: standard, scale: scale)
        }
        return ExerciseRank(exercise: exercise, current: current, peak: peakResult)
    }

    /// Ranks for every exercise the user has logged or submitted, best first.
    static func ranks(exercises: [Exercise], history: TrainingHistory, submissions: [PerformanceRanking], scale: Double, now: Date = Date()) -> [ExerciseRank] {
        let logged = Set(history.samplesByExercise.keys).union(submissions.filter(\.isSubmitted).map(\.exerciseSlug))
        return exercises
            .filter { logged.contains($0.slug) && $0.isRanked }
            .map { rank(for: $0, history: history, submissions: submissions, scale: scale, now: now) }
            .sorted { lhs, rhs in
                let a = lhs.currentResult?.placement.score ?? -1
                let b = rhs.currentResult?.placement.score ?? -1
                if a != b { return a > b }
                return lhs.exercise.name < rhs.exercise.name
            }
    }

    /// Builds the reveal for a new performance, comparing against everything recorded before it.
    static func reveal(for result: RankResult, exercise: Exercise, history: TrainingHistory, rankings: [PerformanceRanking], unit: WeightUnit, scale: Double) -> RankReveal {
        let previousTier = rankings.filter { $0.exerciseSlug == exercise.slug }.map(\.tier).max()
        let previousSets = history.rankableSets(for: exercise.slug, fallbackBodyweight: history.latestBodyweightKg)
            + submittedSets(for: exercise.slug, in: rankings)
        let previousBest = try? RankingEngine.best(of: previousSets, standard: exercise.rankingStandard, scale: scale).get()
        let isBest: Bool
        switch result.method {
        case .relativeLoad:
            // Personal bests compare the lift itself (estimated 1RM), not the bodyweight ratio.
            let previousE1RM = previousSets.compactMap { StrengthMath.estimatedOneRepMax(weight: $0.weightKg, reps: $0.reps) }.max()
            isBest = previousE1RM.map { (result.estimatedOneRepMaxKg ?? 0) > $0 + 1e-9 } ?? false
        default:
            isBest = previousBest.map { result.metric > $0.metric + 1e-9 } ?? false
        }
        return RankReveal(exerciseName: exercise.name, exerciseSlug: exercise.slug, equipment: exercise.equipment,
                          result: result, previousTier: previousTier, previousBestMetric: previousBest?.metric,
                          isPersonalBest: isBest, next: NextTierTarget.make(for: result, increment: unit.toKilograms(unit.increment)),
                          unit: unit)
    }

    /// Validates and stores a submitted performance, returning the reveal to show.
    static func submit(exercise: Exercise, weightKg: Double, reps: Int, bodyweightKg: Double?, history: TrainingHistory,
                       context: ModelContext, unit: WeightUnit, scale: Double, now: Date = Date()) -> Result<RankReveal, RankingFailure> {
        let set = RankableSet(weightKg: weightKg, reps: reps, date: now, bodyweightKg: bodyweightKg)
        switch RankingEngine.evaluate(set, standard: exercise.rankingStandard, scale: scale) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let result):
            let rankings = (try? context.fetch(FetchDescriptor<PerformanceRanking>())) ?? []
            let reveal = reveal(for: result, exercise: exercise, history: history, rankings: rankings, unit: unit, scale: scale)
            context.insert(PerformanceRanking(exerciseSlug: exercise.slug, exerciseName: exercise.name, result: result,
                                              recordedAt: now, sessionID: nil, isSubmitted: true))
            try? context.save()
            return .success(reveal)
        }
    }

    /// Lifts within reach of the next tier, closest first.
    static func closeToRankingUp(_ ranks: [ExerciseRank], minimumProgress: Double = 0.6) -> [ExerciseRank] {
        ranks.filter { rank in
            guard let result = rank.currentResult, result.placement.tier.next != nil else { return false }
            return result.placement.progress >= minimumProgress
        }
        .sorted { ($0.currentResult?.placement.progress ?? 0) > ($1.currentResult?.placement.progress ?? 0) }
    }

    /// Rank-ups in chronological history: entries whose tier beat everything before them for that lift.
    static func rankUps(_ rankings: [PerformanceRanking]) -> [PerformanceRanking] {
        var best: [String: RankTier] = [:]
        var ups: [PerformanceRanking] = []
        for entry in rankings.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            let previous = best[entry.exerciseSlug]
            if entry.tier > .unranked, previous == nil || entry.tier > previous! { ups.append(entry) }
            if previous == nil || entry.tier > previous! { best[entry.exerciseSlug] = entry.tier }
        }
        return ups.reversed()
    }
}
