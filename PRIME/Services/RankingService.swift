import Foundation

struct ExerciseRank: Identifiable {
    let exercise: Exercise
    /// Best set in the last 90 days.
    let current: Result<RankResult, RankingFailure>
    /// Best set ever.
    let peak: RankResult?

    var id: String { exercise.slug }
    var currentResult: RankResult? { if case .success(let result) = current { return result } else { return nil } }
    var failure: RankingFailure? { if case .failure(let failure) = current { return failure } else { return nil } }
}

@MainActor
enum RankingService {
    static let currentWindowDays = 90

    static func rank(for exercise: Exercise, history: TrainingHistory, scale: Double, now: Date = Date()) -> ExerciseRank {
        let fallback = history.latestBodyweightKg
        let all = history.rankableSets(for: exercise.slug, fallbackBodyweight: fallback)
        let since = Calendar.prime.date(byAdding: .day, value: -currentWindowDays, to: now) ?? now
        let recent = all.filter { $0.date >= since }
        let standard = exercise.rankingStandard
        let peakResult: RankResult?
        if case .success(let result) = RankingEngine.best(of: all, standard: standard, scale: scale) { peakResult = result } else { peakResult = nil }
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

    /// Ranks for every exercise the user has logged, best first.
    static func ranks(exercises: [Exercise], history: TrainingHistory, scale: Double, now: Date = Date()) -> [ExerciseRank] {
        let logged = Set(history.samplesByExercise.keys)
        return exercises
            .filter { logged.contains($0.slug) }
            .map { rank(for: $0, history: history, scale: scale, now: now) }
            .sorted { lhs, rhs in
                let a = lhs.currentResult?.placement.score ?? -1
                let b = rhs.currentResult?.placement.score ?? -1
                if a != b { return a > b }
                return lhs.exercise.name < rhs.exercise.name
            }
    }

    static func profileSummary(_ ranks: [ExerciseRank]) -> TrainingProfileSummary {
        TrainingProfileSummary(entries: ranks.compactMap { rank in
            rank.currentResult.map { (score: $0.placement.score, isFreeWeight: rank.exercise.equipment.isFreeWeight) }
        })
    }
}
