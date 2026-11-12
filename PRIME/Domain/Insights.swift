import Foundation

/// An observation drawn only from logged training. Never a prescription.
struct Insight: Identifiable, Equatable {
    enum Kind: String {
        case improving, newBest, matchedBest, plateau, notRecent, lowMuscleVolume, missedSessions
    }

    enum Tone { case positive, neutral, attention }

    let kind: Kind
    let title: String
    let detail: String
    /// Optional, conservative suggestion the user is free to ignore.
    let suggestion: String?
    let exerciseSlug: String?
    let muscle: MuscleGroup?
    let tone: Tone
    let priority: Int

    var id: String { kind.rawValue + (exerciseSlug ?? "") + (muscle?.rawValue ?? "") }

    var symbol: String {
        switch kind {
        case .improving: return "chart.line.uptrend.xyaxis"
        case .newBest: return "trophy.fill"
        case .matchedBest: return "equal.circle.fill"
        case .plateau: return "arrow.right.circle"
        case .notRecent: return "clock.arrow.circlepath"
        case .lowMuscleVolume: return "figure.arms.open"
        case .missedSessions: return "calendar.badge.exclamationmark"
        }
    }
}

struct ImprovedExercise: Identifiable, Equatable {
    let slug: String
    let name: String
    /// Fractional improvement, e.g. 0.08 for 8%.
    let change: Double
    let isOneRepMax: Bool
    var id: String { slug }
}

/// One session's best result for an exercise.
struct SessionBest: Equatable {
    let date: Date
    let value: Double
    let isOneRepMax: Bool
}

enum InsightEngine {
    static let improvementThreshold = 0.02

    /// The best set per session for an exercise: estimated 1RM for loaded work, otherwise reps (or seconds).
    static func sessionBests(_ samples: [SetSample]) -> [SessionBest] {
        Dictionary(grouping: samples, by: \.sessionID).compactMap { _, sets -> SessionBest? in
            guard let date = sets.map(\.date).min() else { return nil }
            let loaded = sets.compactMap { $0.weightKg > 0 ? $0.estimatedOneRepMax : nil }
            if let best = loaded.max() { return SessionBest(date: date, value: best, isOneRepMax: true) }
            guard let reps = sets.map(\.reps).max(), reps > 0 else { return nil }
            return SessionBest(date: date, value: Double(reps), isOneRepMax: false)
        }
        .sorted { $0.date < $1.date }
    }

    static func exerciseInsights(slug: String, name: String, samples: [SetSample], isTimed: Bool, now: Date, calendar: Calendar = .prime) -> [Insight] {
        let bests = sessionBests(samples)
        guard let last = bests.last else { return [] }
        var results: [Insight] = []
        let unit = isTimed ? "hold" : (last.isOneRepMax ? "estimated 1RM" : "best set")
        let daysSince = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.date), to: calendar.startOfDay(for: now)).day ?? 0

        // Not logged recently: only if it was a regular exercise.
        if bests.count >= 3, daysSince >= 21 {
            results.append(Insight(kind: .notRecent, title: "\(name) hasn't been logged for \(daysSince) days",
                                   detail: "You recorded it in \(bests.count) workouts before that.",
                                   suggestion: nil, exerciseSlug: slug, muscle: nil, tone: .neutral, priority: 40))
            return results
        }
        guard daysSince <= 21, bests.count >= 2 else { return results }

        let previous = bests.dropLast()
        let previousBest = previous.map(\.value).max() ?? 0
        if last.value > previousBest * (1 + 0.0001) {
            results.append(Insight(kind: .newBest, title: "New best \(unit) on \(name)",
                                   detail: "Your latest session beat everything you'd recorded before.",
                                   suggestion: nil, exerciseSlug: slug, muscle: nil, tone: .positive, priority: 90))
        } else if previousBest > 0, last.value >= previousBest * 0.995 {
            results.append(Insight(kind: .matchedBest, title: "\(name) matched your best",
                                   detail: "Your latest session equalled your previous best \(unit).",
                                   suggestion: nil, exerciseSlug: slug, muscle: nil, tone: .positive, priority: 60))
        }

        let recent = Array(bests.suffix(4))
        if recent.count == 4 {
            let rising = zip(recent, recent.dropFirst()).allSatisfy { $1.value >= $0.value * 0.999 }
            if rising, let first = recent.first, last.value > first.value * (1 + improvementThreshold) {
                results.append(Insight(kind: .improving, title: "\(name) is trending up",
                                       detail: "It has improved over your last four recorded sessions.",
                                       suggestion: nil, exerciseSlug: slug, muscle: nil, tone: .positive, priority: 80))
            }
        }

        // Plateau: at least four sessions over three weeks and the last three haven't passed the earlier best.
        if bests.count >= 4, let first = bests.first,
           calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0 >= 21 {
            let lastThree = bests.suffix(3).map(\.value)
            let earlierBest = bests.dropLast(3).map(\.value).max() ?? 0
            if earlierBest > 0, (lastThree.max() ?? 0) <= earlierBest * 1.001 {
                results.append(Insight(kind: .plateau, title: "\(name) has held steady",
                                       detail: "Your last three sessions haven't passed your earlier best.",
                                       suggestion: isTimed ? "If you want to progress, you could aim to add a few seconds over the coming weeks."
                                                           : "If you want to progress, you could keep the same weight and build rep consistency before reviewing the load.",
                                       exerciseSlug: slug, muscle: nil, tone: .neutral, priority: 50))
            }
        }
        return results
    }

    /// Muscle groups that have had far less recorded work than the others recently.
    static func balanceInsights(samples: [SetSample], now: Date, calendar: Calendar = .prime) -> [Insight] {
        guard let start = calendar.date(byAdding: .day, value: -28, to: now) else { return [] }
        let recent = samples.filter { $0.date >= start && $0.date <= now }
        let sets = Analytics.setsByMuscle(recent)
        let majors = MuscleGroup.allCases.filter(\.isMajor)
        let counts = majors.map { sets[$0] ?? 0 }.sorted()
        guard counts.count >= 4 else { return [] }
        let median = Double(counts[counts.count / 2])
        guard median >= 8 else { return [] }
        return majors.compactMap { muscle in
            let count = sets[muscle] ?? 0
            guard Double(count) < median * 0.25 else { return nil }
            return Insight(kind: .lowMuscleVolume, title: "\(muscle.displayName): fewer recorded sets",
                           detail: "\(count) working set\(count == 1 ? "" : "s") in the last 4 weeks, against a typical \(Int(median)) for your other main muscle groups. This is recorded activity, not a measure of development.",
                           suggestion: nil, exerciseSlug: nil, muscle: muscle, tone: .attention, priority: 45)
        }
    }

    /// Planned training days in the last four weeks that have no logged workout.
    static func missedSessionInsight(plannedWeekdays: Set<Int>, sessionDates: [Date], trackingSince: Date, now: Date, calendar: Calendar = .prime) -> Insight? {
        guard !plannedWeekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        let trained = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        var planned = 0
        var missed = 0
        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today), day >= calendar.startOfDay(for: trackingSince) else { continue }
            guard plannedWeekdays.contains(Weekday.index(of: day, calendar: calendar)) else { continue }
            planned += 1
            if !trained.contains(day) { missed += 1 }
        }
        guard planned >= 4, missed >= 3, Double(missed) / Double(planned) >= 0.3 else { return nil }
        return Insight(kind: .missedSessions, title: "\(missed) of your last \(planned) planned sessions weren't logged",
                       detail: "Based on your current timetable. If the plan doesn't fit your week any more, you can move or remove sessions.",
                       suggestion: nil, exerciseSlug: nil, muscle: nil, tone: .attention, priority: 55)
    }

    static func all(history: TrainingHistory, plannedWeekdays: Set<Int>, trackingSince: Date, now: Date = Date(), timedSlugs: Set<String> = []) -> [Insight] {
        var results: [Insight] = []
        for slug in history.exerciseSlugsByRecency {
            let samples = history.samples(for: slug)
            results += exerciseInsights(slug: slug, name: history.exerciseName(for: slug) ?? slug, samples: samples,
                                        isTimed: timedSlugs.contains(slug), now: now)
        }
        results += balanceInsights(samples: history.samples, now: now)
        if let missed = missedSessionInsight(plannedWeekdays: plannedWeekdays, sessionDates: history.sessions.map(\.startedAt),
                                             trackingSince: trackingSince, now: now) {
            results.append(missed)
        }
        return results.sorted { $0.priority == $1.priority ? $0.title < $1.title : $0.priority > $1.priority }
    }

    /// Exercises whose best per-session result rose most over a window, for the dashboard.
    static func mostImproved(history: TrainingHistory, days: Int = 60, now: Date = Date(), calendar: Calendar = .prime) -> [ImprovedExercise] {
        guard let start = calendar.date(byAdding: .day, value: -days, to: now) else { return [] }
        return history.exerciseSlugsByRecency.compactMap { slug in
            let bests = sessionBests(history.samples(for: slug)).filter { $0.date >= start }
            guard bests.count >= 2, let first = bests.first, let best = bests.map(\.value).max(), first.value > 0, best > first.value else { return nil }
            return ImprovedExercise(slug: slug, name: history.exerciseName(for: slug) ?? slug, change: (best - first.value) / first.value, isOneRepMax: first.isOneRepMax)
        }
        .sorted { $0.change > $1.change }
    }
}
