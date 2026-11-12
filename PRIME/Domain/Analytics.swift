import Foundation

struct TimeBucket: Identifiable, Equatable {
    let start: Date
    let value: Double
    var id: Date { start }
}

struct ExerciseVolume: Identifiable, Equatable {
    let slug: String
    let name: String
    let volume: Double
    var id: String { slug }
}

struct ExercisePoint: Identifiable, Equatable {
    let date: Date
    let sessionID: UUID
    let value: Double
    var id: UUID { sessionID }
}

enum BucketSize: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var displayName: String { self == .week ? "Weekly" : "Monthly" }
}

enum Analytics {
    static func totalVolume(_ samples: [SetSample]) -> Double {
        samples.reduce(0) { $0 + $1.volume }
    }

    /// Repetitions across sets. Timed holds aren't reps, so they're left out.
    static func totalReps(_ samples: [SetSample]) -> Int {
        samples.reduce(0) { $0 + $1.repCount }
    }

    /// Working sets per bucket for one muscle (primary involvement only).
    static func sets(for muscle: MuscleGroup, in samples: [SetSample], by bucket: BucketSize, interval: DateInterval, calendar: Calendar = .prime) -> [TimeBucket] {
        let starts = bucketStarts(bucket, in: interval, calendar: calendar)
        var counts: [Date: Double] = [:]
        for sample in samples where interval.contains(sample.date) && sample.primaryMuscles.contains(muscle) {
            counts[bucketStart(for: sample.date, bucket: bucket, calendar: calendar), default: 0] += 1
        }
        return starts.map { TimeBucket(start: $0, value: counts[$0] ?? 0) }
    }

    /// Exercises that trained a muscle directly, with their set counts, most first.
    static func exercises(for muscle: MuscleGroup, in samples: [SetSample]) -> [(slug: String, name: String, sets: Int)] {
        Dictionary(grouping: samples.filter { $0.primaryMuscles.contains(muscle) }, by: \.exerciseSlug)
            .map { (slug: $0.key, name: $0.value.last?.exerciseName ?? $0.key, sets: $0.value.count) }
            .sorted { $0.sets == $1.sets ? $0.name < $1.name : $0.sets > $1.sets }
    }

    /// Volume grouped into weeks or months, including empty buckets so charts show gaps honestly.
    static func volume(_ samples: [SetSample], by bucket: BucketSize, in interval: DateInterval, calendar: Calendar = .prime) -> [TimeBucket] {
        let starts = bucketStarts(bucket, in: interval, calendar: calendar)
        var totals: [Date: Double] = [:]
        for sample in samples where interval.contains(sample.date) {
            totals[bucketStart(for: sample.date, bucket: bucket, calendar: calendar), default: 0] += sample.volume
        }
        return starts.map { TimeBucket(start: $0, value: totals[$0] ?? 0) }
    }

    /// Volume per day for the seven days of the week containing `date` (Monday first).
    static func dailyVolume(_ samples: [SetSample], weekContaining date: Date, calendar: Calendar = .prime) -> [Double] {
        let weekStart = calendar.startOfWeek(for: date)
        var totals = Array(repeating: 0.0, count: 7)
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let offset = calendar.dateComponents([.day], from: weekStart, to: day).day ?? -1
            if (0..<7).contains(offset) { totals[offset] += sample.volume }
        }
        return totals
    }

    /// Each set's volume is credited to the exercise's primary muscles.
    static func volumeByMuscle(_ samples: [SetSample]) -> [MuscleGroup: Double] {
        var totals: [MuscleGroup: Double] = [:]
        for sample in samples {
            for muscle in sample.primaryMuscles { totals[muscle, default: 0] += sample.volume }
        }
        return totals
    }

    /// Working sets per primary muscle, which is fairer than volume for bodyweight work.
    static func setsByMuscle(_ samples: [SetSample]) -> [MuscleGroup: Int] {
        var totals: [MuscleGroup: Int] = [:]
        for sample in samples {
            for muscle in sample.primaryMuscles { totals[muscle, default: 0] += 1 }
        }
        return totals
    }

    static func volumeByExercise(_ samples: [SetSample]) -> [ExerciseVolume] {
        let grouped = Dictionary(grouping: samples, by: \.exerciseSlug)
        return grouped
            .map { slug, sets in ExerciseVolume(slug: slug, name: sets.last?.exerciseName ?? slug, volume: totalVolume(sets)) }
            .filter { $0.volume > 0 }
            .sorted { $0.volume > $1.volume }
    }

    /// Best estimated 1RM per session for one exercise.
    static func oneRepMaxProgression(_ samples: [SetSample]) -> [ExercisePoint] {
        perSession(samples) { sets in sets.compactMap(\.estimatedOneRepMax).max() }
    }

    /// Heaviest weight per session for one exercise.
    static func weightProgression(_ samples: [SetSample]) -> [ExercisePoint] {
        perSession(samples) { sets in sets.map(\.weightKg).filter { $0 > 0 }.max() }
    }

    /// Most reps in a single set per session (bodyweight exercises).
    static func repProgression(_ samples: [SetSample]) -> [ExercisePoint] {
        perSession(samples) { sets in sets.map { Double($0.reps) }.max() }
    }

    static func sessionVolumeProgression(_ samples: [SetSample]) -> [ExercisePoint] {
        perSession(samples) { sets in
            let volume = totalVolume(sets)
            return volume > 0 ? volume : nil
        }
    }

    private static func perSession(_ samples: [SetSample], value: ([SetSample]) -> Double?) -> [ExercisePoint] {
        Dictionary(grouping: samples, by: \.sessionID)
            .compactMap { id, sets -> ExercisePoint? in
                guard let date = sets.map(\.date).min(), let v = value(sets) else { return nil }
                return ExercisePoint(date: date, sessionID: id, value: v)
            }
            .sorted { $0.date < $1.date }
    }

    /// Workouts per bucket.
    static func frequency(_ sessions: [SessionSummary], by bucket: BucketSize, in interval: DateInterval, calendar: Calendar = .prime) -> [TimeBucket] {
        let starts = bucketStarts(bucket, in: interval, calendar: calendar)
        var counts: [Date: Double] = [:]
        for session in sessions where interval.contains(session.startedAt) {
            counts[bucketStart(for: session.startedAt, bucket: bucket, calendar: calendar), default: 0] += 1
        }
        return starts.map { TimeBucket(start: $0, value: counts[$0] ?? 0) }
    }

    /// Consecutive weeks (Mon–Sun) with at least `weeklyGoal` workouts. The current week
    /// only counts once the goal is hit, and never breaks the streak while it's in progress.
    static func weekStreak(sessionDates: [Date], weeklyGoal: Int, now: Date = Date(), calendar: Calendar = .prime) -> Int {
        let goal = max(1, weeklyGoal)
        var counts: [Date: Int] = [:]
        for date in sessionDates { counts[calendar.startOfWeek(for: date), default: 0] += 1 }
        var week = calendar.startOfWeek(for: now)
        var streak = 0
        if (counts[week] ?? 0) >= goal { streak += 1 }
        while true {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
            if (counts[week] ?? 0) >= goal { streak += 1 } else { break }
        }
        return streak
    }

    /// Longest run of goal-meeting weeks ever.
    static func bestWeekStreak(sessionDates: [Date], weeklyGoal: Int, calendar: Calendar = .prime) -> Int {
        let goal = max(1, weeklyGoal)
        var counts: [Date: Int] = [:]
        for date in sessionDates { counts[calendar.startOfWeek(for: date), default: 0] += 1 }
        let weeks = counts.filter { $0.value >= goal }.keys.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for week in weeks {
            if let previous, calendar.date(byAdding: .weekOfYear, value: 1, to: previous) == week {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        return best
    }

    /// Days with at least one completed workout.
    static func trainedDays(_ sessions: [SessionSummary], calendar: Calendar = .prime) -> Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    // MARK: Buckets

    static func bucketStart(for date: Date, bucket: BucketSize, calendar: Calendar) -> Date {
        bucket == .week ? calendar.startOfWeek(for: date) : calendar.startOfMonth(for: date)
    }

    static func bucketStarts(_ bucket: BucketSize, in interval: DateInterval, calendar: Calendar) -> [Date] {
        var starts: [Date] = []
        var cursor = bucketStart(for: interval.start, bucket: bucket, calendar: calendar)
        let component: Calendar.Component = bucket == .week ? .weekOfYear : .month
        while cursor <= interval.end && starts.count < 600 {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return starts
    }
}

/// Date ranges used by every analytics screen.
enum AnalyticsRange: String, CaseIterable, Identifiable {
    case week, month, quarter, half, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .half: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var longLabel: String {
        switch self {
        case .week: return "the last 7 days"
        case .month: return "the last 30 days"
        case .quarter: return "the last 90 days"
        case .half: return "the last 6 months"
        case .year: return "the last year"
        case .all: return "all time"
        }
    }

    func interval(now: Date = Date(), earliest: Date?, calendar: Calendar = .prime) -> DateInterval {
        let end = now
        let start: Date
        switch self {
        case .week: start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        case .month: start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        case .quarter: start = calendar.date(byAdding: .day, value: -89, to: end) ?? end
        case .half: start = calendar.date(byAdding: .month, value: -6, to: end) ?? end
        case .year: start = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        case .all: start = min(earliest ?? end, calendar.date(byAdding: .month, value: -1, to: end) ?? end)
        }
        return DateInterval(start: calendar.startOfDay(for: start), end: end)
    }

    var preferredBucket: BucketSize {
        switch self {
        case .week, .month, .quarter, .half: return .week
        case .year, .all: return .month
        }
    }
}

/// A muscle with a number attached (sets, volume or rank score), for charts and lists.
struct MuscleScore: Identifiable, Equatable {
    let muscle: MuscleGroup
    let score: Double
    var id: MuscleGroup { muscle }
}
