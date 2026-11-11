import Foundation
import Observation
import SwiftData

/// Holds a read-only snapshot of completed training so every screen computes from the
/// same data with one fetch, instead of each view walking the database on every render.
@MainActor
@Observable
final class TrainingStore {
    private(set) var history: TrainingHistory = .empty
    private(set) var revision = 0

    func refresh(_ context: ModelContext) {
        let completed = SessionStatus.completed.rawValue
        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == completed },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        let entries = (try? context.fetch(FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        history = TrainingStore.makeHistory(sessions: sessions, bodyweights: entries)
        revision += 1
    }

    static func makeHistory(sessions: [WorkoutSession], bodyweights: [BodyweightEntry]) -> TrainingHistory {
        var samples: [SetSample] = []
        var summaries: [SessionSummary] = []
        for session in sessions where session.status == .completed {
            var setCount = 0
            var exerciseCount = 0
            var volume = 0.0
            for entry in session.sortedExercises where !entry.isSkipped {
                let sets = entry.sortedSets.filter { $0.isCompleted && !$0.isWarmup && ($0.reps ?? 0) > 0 }
                if !sets.isEmpty { exerciseCount += 1 }
                for (index, set) in sets.enumerated() {
                    let sample = SetSample(
                        sessionID: session.uuid,
                        date: set.completedAt ?? session.startedAt.addingTimeInterval(Double(index)),
                        exerciseSlug: entry.exerciseSlug,
                        exerciseName: entry.exerciseName,
                        equipment: Equipment(rawValue: entry.equipmentRaw),
                        primaryMuscles: entry.primaryMuscles,
                        weightKg: max(0, set.weightKg ?? 0),
                        reps: set.reps ?? 0,
                        bodyweightKg: session.bodyweightKg,
                        setIndex: index
                    )
                    samples.append(sample)
                    volume += sample.volume
                    setCount += 1
                }
            }
            summaries.append(SessionSummary(
                id: session.uuid, name: session.name, startedAt: session.startedAt,
                duration: session.duration, volume: volume, setCount: setCount, exerciseCount: exerciseCount
            ))
        }
        let points = bodyweights.map { BodyweightPoint(date: $0.date, weightKg: $0.weightKg) }
        return TrainingHistory(samples: samples, sessions: summaries, bodyweights: points)
    }
}
