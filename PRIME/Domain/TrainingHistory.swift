import Foundation

/// A completed working set, flattened out of the database so analytics are pure and testable.
struct SetSample: Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let date: Date
    let exerciseSlug: String
    let exerciseName: String
    let equipment: Equipment?
    let primaryMuscles: [MuscleGroup]
    let weightKg: Double
    let reps: Int
    let bodyweightKg: Double?
    /// Order within its exercise in the session.
    let setIndex: Int

    init(id: UUID = UUID(), sessionID: UUID, date: Date, exerciseSlug: String, exerciseName: String,
         equipment: Equipment?, primaryMuscles: [MuscleGroup], weightKg: Double, reps: Int,
         bodyweightKg: Double? = nil, setIndex: Int = 0) {
        self.id = id
        self.setIndex = setIndex
        self.sessionID = sessionID
        self.date = date
        self.exerciseSlug = exerciseSlug
        self.exerciseName = exerciseName
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.weightKg = weightKg
        self.reps = reps
        self.bodyweightKg = bodyweightKg
    }

    var volume: Double { StrengthMath.setVolume(weight: weightKg, reps: reps) }
    var estimatedOneRepMax: Double? { StrengthMath.estimatedOneRepMax(weight: weightKg, reps: reps) }
    var rankable: RankableSet { RankableSet(weightKg: weightKg, reps: reps, date: date, bodyweightKg: bodyweightKg) }
}

struct SessionSummary: Equatable, Identifiable {
    let id: UUID
    let name: String
    let startedAt: Date
    let duration: TimeInterval
    let volume: Double
    let setCount: Int
    let exerciseCount: Int
}

struct BodyweightPoint: Equatable {
    let date: Date
    let weightKg: Double
}

/// Read-only snapshot of everything the user has completed.
struct TrainingHistory {
    let samples: [SetSample]
    let sessions: [SessionSummary]
    let bodyweights: [BodyweightPoint]
    let samplesByExercise: [String: [SetSample]]

    static let empty = TrainingHistory(samples: [], sessions: [], bodyweights: [])

    init(samples: [SetSample], sessions: [SessionSummary], bodyweights: [BodyweightPoint]) {
        self.samples = samples.sorted { $0.date < $1.date }
        self.sessions = sessions.sorted { $0.startedAt > $1.startedAt }
        self.bodyweights = bodyweights.sorted { $0.date < $1.date }
        self.samplesByExercise = Dictionary(grouping: self.samples, by: \.exerciseSlug)
    }

    var isEmpty: Bool { sessions.isEmpty }
    var latestBodyweightKg: Double? { bodyweights.last?.weightKg }

    /// Latest entry on or before the date; otherwise the earliest entry after it.
    func bodyweight(on date: Date) -> Double? {
        if let before = bodyweights.last(where: { $0.date <= date }) { return before.weightKg }
        return bodyweights.first?.weightKg
    }

    func samples(for slug: String, in interval: DateInterval? = nil) -> [SetSample] {
        let all = samplesByExercise[slug] ?? []
        guard let interval else { return all }
        return all.filter { interval.contains($0.date) }
    }

    func samples(in interval: DateInterval) -> [SetSample] {
        samples.filter { interval.contains($0.date) }
    }

    func sessions(in interval: DateInterval) -> [SessionSummary] {
        sessions.filter { interval.contains($0.startedAt) }
    }

    /// Rankable sets for an exercise, each carrying the bodyweight logged nearest to it.
    func rankableSets(for slug: String, since: Date? = nil, fallbackBodyweight: Double? = nil) -> [RankableSet] {
        samples(for: slug)
            .filter { since == nil || $0.date >= since! }
            .map { sample in
                var set = sample.rankable
                set.bodyweightKg = sample.bodyweightKg ?? bodyweight(on: sample.date) ?? fallbackBodyweight
                return set
            }
    }

    /// Exercises the user has logged, most recent first.
    var exerciseSlugsByRecency: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for sample in samples.reversed() where !seen.contains(sample.exerciseSlug) {
            seen.insert(sample.exerciseSlug)
            result.append(sample.exerciseSlug)
        }
        return result
    }

    func exerciseName(for slug: String) -> String? { samplesByExercise[slug]?.last?.exerciseName }

    /// The sets from the most recent session that included this exercise, in order.
    func lastPerformance(for slug: String) -> [SetSample] {
        let all = samples(for: slug)
        guard let lastSession = all.last?.sessionID else { return [] }
        return all.filter { $0.sessionID == lastSession }.sorted { $0.setIndex < $1.setIndex }
    }

    func lastPerformedDate(for slug: String) -> Date? { samples(for: slug).last?.date }

    func sessionCount(for slug: String) -> Int { Set(samples(for: slug).map(\.sessionID)).count }

    /// Personal-best snapshot for one exercise.
    func records(for slug: String) -> RecordSnapshot { RecordSnapshot.from(samples(for: slug)) }

    var firstSessionDate: Date? { sessions.last?.startedAt }
}
