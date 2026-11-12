import Foundation
import SwiftData

struct RecordLine: Identifiable, Equatable {
    let id = UUID()
    let exerciseSlug: String
    let exerciseName: String
    let achievement: PRAchievement
}

struct RankChange: Identifiable, Equatable {
    let exerciseSlug: String
    let exerciseName: String
    let from: RankTier?
    let to: RankTier
    let result: RankResult
    var id: String { exerciseSlug }
}

struct WorkoutSummary: Identifiable {
    let id = UUID()
    let sessionID: UUID
    let name: String
    let duration: TimeInterval
    let volumeKg: Double
    let setCount: Int
    let exerciseCount: Int
    let repCount: Int
    let muscles: [MuscleGroup]
    let records: [RecordLine]
    let rankChanges: [RankChange]
}

enum WorkoutError: LocalizedError, Equatable {
    case noCompletedSets
    case invalidSet(String)

    var errorDescription: String? {
        switch self {
        case .noCompletedSets: return "Complete at least one set, or discard this workout."
        case .invalidSet(let reason): return reason
        }
    }
}

/// Placeholder values shown in an empty set row, and adopted if the set is ticked off as-is.
struct SetSuggestion: Equatable {
    var weightKg: Double?
    var reps: Int?
    var source: Source

    enum Source: Equatable { case lastWorkout, previousSet, target, none }
}

@MainActor
enum WorkoutService {
    // MARK: Lookup

    static func activeSession(in context: ModelContext) -> WorkoutSession? {
        let active = SessionStatus.active.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func defaultName(for date: Date = Date(), calendar: Calendar = .prime) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning workout"
        case 12..<17: return "Afternoon workout"
        case 17..<22: return "Evening workout"
        default: return "Late workout"
        }
    }

    // MARK: Starting

    @discardableResult
    static func start(plan: WorkoutPlan?, context: ModelContext, history: TrainingHistory, now: Date = Date()) -> WorkoutSession {
        let session = WorkoutSession(
            name: plan?.name ?? defaultName(for: now),
            planID: plan?.uuid,
            bodyweightKg: history.latestBodyweightKg,
            startedAt: now
        )
        context.insert(session)
        if let plan {
            var position = 0
            for entry in plan.sortedEntries {
                guard let exercise = entry.exercise else { continue }
                let item = ExerciseSession(position: position, exercise: exercise, restSeconds: entry.restSeconds,
                                           targetReps: entry.targetReps, targetWeightKg: entry.targetWeightKg)
                context.insert(item)
                item.session = session
                for index in 0..<max(1, entry.targetSets) {
                    let set = ExerciseSet(position: index)
                    context.insert(set)
                    set.exerciseSession = item
                }
                position += 1
            }
        }
        try? context.save()
        return session
    }

    /// Starts an empty workout with one exercise in it.
    @discardableResult
    static func start(exercise: Exercise, restSeconds: Int, context: ModelContext, history: TrainingHistory, now: Date = Date()) -> WorkoutSession {
        let session = start(plan: nil, context: context, history: history, now: now)
        session.name = exercise.name
        addExercise(exercise, to: session, restSeconds: restSeconds, context: context, history: history)
        return session
    }

    @discardableResult
    static func addExercise(_ exercise: Exercise, to session: WorkoutSession, restSeconds: Int, context: ModelContext, history: TrainingHistory) -> ExerciseSession {
        let last = history.lastPerformance(for: exercise.slug)
        let item = ExerciseSession(position: session.nextPosition, exercise: exercise, restSeconds: restSeconds)
        context.insert(item)
        item.session = session
        for index in 0..<max(3, min(last.count, 8)) {
            let set = ExerciseSet(position: index)
            context.insert(set)
            set.exerciseSession = item
        }
        try? context.save()
        return item
    }

    /// Swaps the exercise in place. Logged values belong to the old exercise, so they're cleared.
    static func replace(_ item: ExerciseSession, with exercise: Exercise, context: ModelContext) {
        item.adopt(exercise)
        item.isSkipped = false
        item.targetWeightKg = nil
        for set in item.sets {
            set.weightKg = nil
            set.reps = nil
            set.isCompleted = false
            set.completedAt = nil
        }
        try? context.save()
    }

    static func remove(_ item: ExerciseSession, from session: WorkoutSession, context: ModelContext) {
        context.delete(item)
        try? context.save()
        for (index, entry) in session.sortedExercises.filter({ $0.persistentModelID != item.persistentModelID }).enumerated() {
            entry.position = index
        }
        try? context.save()
    }

    static func move(_ session: WorkoutSession, from source: IndexSet, to destination: Int, context: ModelContext) {
        var ordered = session.sortedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() { item.position = index }
        try? context.save()
    }

    @discardableResult
    static func addSet(to item: ExerciseSession, context: ModelContext) -> ExerciseSet {
        let set = ExerciseSet(position: item.nextSetPosition)
        context.insert(set)
        set.exerciseSession = item
        try? context.save()
        return set
    }

    static func removeSet(_ set: ExerciseSet, from item: ExerciseSession, context: ModelContext) {
        let remaining = item.sortedSets.filter { $0.persistentModelID != set.persistentModelID }
        context.delete(set)
        for (index, other) in remaining.enumerated() { other.position = index }
        try? context.save()
    }

    // MARK: Sets

    static func suggestion(for set: ExerciseSet, in item: ExerciseSession, history: TrainingHistory) -> SetSuggestion {
        let ordered = item.sortedSets
        let index = ordered.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0
        let last = history.lastPerformance(for: item.exerciseSlug)
        if index < last.count {
            return SetSuggestion(weightKg: last[index].weightKg, reps: last[index].reps, source: .lastWorkout)
        }
        if index > 0, let previous = ordered[..<index].last(where: { $0.reps != nil }) {
            return SetSuggestion(weightKg: previous.weightKg, reps: previous.reps, source: .previousSet)
        }
        if let lastSet = last.last {
            return SetSuggestion(weightKg: lastSet.weightKg, reps: lastSet.reps, source: .lastWorkout)
        }
        if item.targetReps != nil || item.targetWeightKg != nil {
            return SetSuggestion(weightKg: item.targetWeightKg, reps: item.targetReps, source: .target)
        }
        return SetSuggestion(weightKg: nil, reps: nil, source: .none)
    }

    /// Marks a set done after validating it. Returns the records it beats so the UI can celebrate.
    static func complete(_ set: ExerciseSet, in item: ExerciseSession, session: WorkoutSession, history: TrainingHistory,
                         context: ModelContext, now: Date = Date()) throws -> [RecordKind] {
        let timed = ExerciseLibrary.shared.isTimed(item.exerciseSlug)
        if let error = InputValidator.completedSetError(weightKg: set.weightKg, reps: set.reps, requiresLoad: item.equipment.requiresLoad && !timed, timed: timed) {
            throw WorkoutError.invalidSet(error.errorDescription ?? "Check this set")
        }
        set.isCompleted = true
        set.completedAt = now
        try? context.save()

        guard !set.isWarmup, let reps = set.reps else { return [] }
        var snapshot = history.records(for: item.exerciseSlug)
        guard snapshot.hasHistory else { return [] }
        // Earlier sets in this workout count too, so the same record isn't announced twice.
        let earlier = session.exercises
            .filter { $0.exerciseSlug == item.exerciseSlug }
            .flatMap(\.sets)
            .filter { $0.isCompleted && !$0.isWarmup && $0.persistentModelID != set.persistentModelID }
        if timed {
            snapshot.absorbSession(earlier.map { (weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0) }, timed: true)
        } else {
            for other in earlier { snapshot.absorb(weightKg: other.weightKg ?? 0, reps: other.reps ?? 0) }
        }
        return PRDetector.recordsBeaten(weightKg: set.weightKg ?? 0, reps: reps, against: snapshot, timed: timed)
    }

    static func uncomplete(_ set: ExerciseSet, context: ModelContext) {
        set.isCompleted = false
        set.completedAt = nil
        try? context.save()
    }

    // MARK: Rest timer

    static func startRest(_ session: WorkoutSession, seconds: Int, label: String, notify: Bool, now: Date = Date()) {
        guard seconds > 0 else { return }
        session.restPausedRemaining = nil
        session.restEndsAt = now.addingTimeInterval(TimeInterval(seconds))
        session.restTotalSeconds = seconds
        session.restExerciseName = label
        if notify, let end = session.restEndsAt {
            NotificationService.shared.scheduleRestTimer(endsAt: end, label: label)
        }
    }

    static func adjustRest(_ session: WorkoutSession, by delta: Int, notify: Bool, now: Date = Date()) {
        guard let end = session.restEndsAt else { return }
        let newEnd = max(now.addingTimeInterval(1), end.addingTimeInterval(TimeInterval(delta)))
        session.restEndsAt = newEnd
        session.restTotalSeconds = max(1, session.restTotalSeconds + delta)
        if notify { NotificationService.shared.scheduleRestTimer(endsAt: newEnd, label: session.restExerciseName) }
    }

    static func endRest(_ session: WorkoutSession) {
        session.restEndsAt = nil
        session.restPausedRemaining = nil
        NotificationService.shared.cancelRestTimer()
    }

    static func pauseRest(_ session: WorkoutSession, now: Date = Date()) {
        guard let end = session.restEndsAt else { return }
        session.restPausedRemaining = max(1, Int(end.timeIntervalSince(now).rounded(.up)))
        session.restEndsAt = nil
        NotificationService.shared.cancelRestTimer()
    }

    static func resumeRest(_ session: WorkoutSession, notify: Bool, now: Date = Date()) {
        guard let remaining = session.restPausedRemaining else { return }
        session.restPausedRemaining = nil
        session.restEndsAt = now.addingTimeInterval(TimeInterval(remaining))
        if notify, let end = session.restEndsAt { NotificationService.shared.scheduleRestTimer(endsAt: end, label: session.restExerciseName) }
    }

    /// Restarts the timer at a preset length, keeping the same exercise label.
    static func setRest(_ session: WorkoutSession, seconds: Int, notify: Bool, now: Date = Date()) {
        session.restPausedRemaining = nil
        startRest(session, seconds: seconds, label: session.restExerciseName, notify: notify, now: now)
    }

    // MARK: Finishing

    static func hasIncompleteSetsWithValues(_ session: WorkoutSession) -> Bool {
        session.exercises.filter { !$0.isSkipped }.flatMap(\.sets).contains { !$0.isCompleted && $0.reps != nil }
    }

    static func finish(_ session: WorkoutSession, context: ModelContext, store: TrainingStore, profile: UserProfile?,
                       exercises: [Exercise], now: Date = Date()) throws -> WorkoutSummary {
        guard !session.completedSets.isEmpty else { throw WorkoutError.noCompletedSets }

        // Unfinished sets are dropped; an exercise with nothing done is kept as skipped.
        for item in session.exercises {
            for set in item.sets where !set.isCompleted { context.delete(set) }
            if !item.sets.contains(where: \.isCompleted) { item.isSkipped = true }
            for (index, set) in item.sets.filter(\.isCompleted).sorted(by: { $0.position < $1.position }).enumerated() {
                set.position = index
            }
        }

        let previousHistory = store.history
        session.status = .completed
        session.endedAt = now
        session.restEndsAt = nil
        session.restPausedRemaining = nil
        if session.bodyweightKg == nil { session.bodyweightKg = previousHistory.latestBodyweightKg }
        try context.save()
        NotificationService.shared.cancelRestTimer()

        store.refresh(context)
        let sessionSamples = store.history.samples.filter { $0.sessionID == session.uuid }
        let exercisesBySlug = Dictionary(exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let evaluation = RecordService.evaluate(
            sessionID: session.uuid, date: session.startedAt, samples: sessionSamples,
            snapshotFor: { previousHistory.records(for: $0) },
            exercisesBySlug: exercisesBySlug, history: store.history, scale: profile?.tierScale ?? 1
        )

        var changes: [RankChange] = []
        for (slug, result) in evaluation.ranks {
            let previousPeak = RecordService.peakTier(for: slug, context: context)
            context.insert(PerformanceRanking(exerciseSlug: slug, exerciseName: exercisesBySlug[slug]?.name ?? slug,
                                              result: result, recordedAt: session.startedAt, sessionID: session.uuid))
            if previousPeak == nil || result.placement.tier > previousPeak! {
                changes.append(RankChange(exerciseSlug: slug, exerciseName: exercisesBySlug[slug]?.name ?? slug,
                                          from: previousPeak, to: result.placement.tier, result: result))
            }
        }
        for line in evaluation.records {
            context.insert(PersonalRecord(exerciseSlug: line.exerciseSlug, exerciseName: line.exerciseName,
                                          kind: line.achievement.kind, value: line.achievement.value,
                                          weightKg: line.achievement.weightKg, reps: line.achievement.reps,
                                          previousValue: line.achievement.previous, achievedAt: now, sessionID: session.uuid))
        }
        try context.save()

        if let profile, profile.notifyPersonalRecords, !evaluation.records.isEmpty {
            NotificationService.shared.postRecordsSummary(count: evaluation.records.count, workoutName: session.name)
        }

        let summary = store.history.sessions.first { $0.id == session.uuid }
        var muscles: [MuscleGroup] = []
        for sample in sessionSamples { for muscle in sample.primaryMuscles where !muscles.contains(muscle) { muscles.append(muscle) } }
        return WorkoutSummary(
            sessionID: session.uuid, name: session.name, duration: session.duration,
            volumeKg: summary?.volume ?? session.totalVolume, setCount: summary?.setCount ?? session.completedSets.count,
            exerciseCount: summary?.exerciseCount ?? 0, repCount: summary?.repCount ?? 0, muscles: muscles,
            records: evaluation.records, rankChanges: changes.sorted { $0.to > $1.to }
        )
    }

    static func discard(_ session: WorkoutSession, context: ModelContext) {
        NotificationService.shared.cancelRestTimer()
        context.delete(session)
        try? context.save()
    }

    /// Deletes a finished workout and rebuilds records and rank history without it.
    static func deleteCompleted(_ session: WorkoutSession, context: ModelContext, store: TrainingStore, profile: UserProfile?, exercises: [Exercise]) {
        context.delete(session)
        try? context.save()
        store.refresh(context)
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profile?.tierScale ?? 1)
    }
}

/// Personal records and rank history are derived data, so they can always be rebuilt from workouts.
@MainActor
enum RecordService {
    struct Evaluation {
        var records: [RecordLine] = []
        var ranks: [(slug: String, result: RankResult)] = []
    }

    static func evaluate(sessionID: UUID, date: Date, samples: [SetSample], snapshotFor: (String) -> RecordSnapshot,
                         exercisesBySlug: [String: Exercise], history: TrainingHistory, scale: Double) -> Evaluation {
        var evaluation = Evaluation()
        let bySlug = Dictionary(grouping: samples, by: \.exerciseSlug)
        for slug in bySlug.keys.sorted() {
            guard let sets = bySlug[slug] else { continue }
            let name = sets.first?.exerciseName ?? slug
            let pairs = sets.map { (weightKg: $0.weightKg, reps: $0.reps) }
            let timed = sets.first?.isTimed ?? false
            for achievement in PRDetector.sessionRecords(sets: pairs, against: snapshotFor(slug), timed: timed) {
                evaluation.records.append(RecordLine(exerciseSlug: slug, exerciseName: name, achievement: achievement))
            }
            if !timed, let exercise = exercisesBySlug[slug], exercise.isRanked {
                let rankable = sets.map { sample -> RankableSet in
                    var set = sample.rankable
                    set.bodyweightKg = sample.bodyweightKg ?? history.bodyweight(on: date)
                    return set
                }
                if case .success(let result) = RankingEngine.best(of: rankable, standard: exercise.rankingStandard, scale: scale) {
                    evaluation.ranks.append((slug, result))
                }
            }
        }
        return evaluation
    }

    static func peakTier(for slug: String, context: ModelContext) -> RankTier? {
        var descriptor = FetchDescriptor<PerformanceRanking>(
            predicate: #Predicate { $0.exerciseSlug == slug },
            sortBy: [SortDescriptor(\.tierRaw, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let top = try? context.fetch(descriptor).first else { return nil }
        return top.tier
    }

    /// Replays every completed workout in order and regenerates records and workout rank snapshots.
    /// Performances the user submitted for ranking are their own history and are kept as recorded.
    static func rebuildAll(context: ModelContext, history: TrainingHistory, exercises: [Exercise], scale: Double) {
        for record in (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [] { context.delete(record) }
        for ranking in (try? context.fetch(FetchDescriptor<PerformanceRanking>())) ?? [] where !ranking.isSubmitted { context.delete(ranking) }

        let exercisesBySlug = Dictionary(exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let bySession = Dictionary(grouping: history.samples, by: \.sessionID)
        var snapshots: [String: RecordSnapshot] = [:]

        for session in history.sessions.reversed() {
            let samples = bySession[session.id] ?? []
            let achievedAt = session.startedAt.addingTimeInterval(session.duration)
            let evaluation = evaluate(sessionID: session.id, date: session.startedAt, samples: samples,
                                      snapshotFor: { snapshots[$0] ?? .empty },
                                      exercisesBySlug: exercisesBySlug, history: history, scale: scale)
            for line in evaluation.records {
                context.insert(PersonalRecord(exerciseSlug: line.exerciseSlug, exerciseName: line.exerciseName,
                                              kind: line.achievement.kind, value: line.achievement.value,
                                              weightKg: line.achievement.weightKg, reps: line.achievement.reps,
                                              previousValue: line.achievement.previous, achievedAt: achievedAt, sessionID: session.id))
            }
            for (slug, result) in evaluation.ranks {
                context.insert(PerformanceRanking(exerciseSlug: slug, exerciseName: exercisesBySlug[slug]?.name ?? slug,
                                                  result: result, recordedAt: session.startedAt, sessionID: session.id))
            }
            for (slug, sets) in Dictionary(grouping: samples, by: \.exerciseSlug) {
                var snapshot = snapshots[slug] ?? .empty
                snapshot.absorbSession(sets.map { (weightKg: $0.weightKg, reps: $0.reps) }, timed: sets.first?.isTimed ?? false)
                snapshots[slug] = snapshot
            }
        }
        try? context.save()
    }
}
