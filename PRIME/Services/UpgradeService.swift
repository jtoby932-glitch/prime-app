import Foundation
import SwiftData

/// Data upgrades that SwiftData's schema migration can't do on its own. Each step runs once,
/// after the catalogue is refreshed, and only changes derived data or converts formats; it never
/// deletes workouts, routines, bodyweight or anything the user entered.
@MainActor
enum UpgradeService {
    static let key = "prime.dataVersion"
    static let current = 2

    static func runIfNeeded(context: ModelContext, store: TrainingStore, defaults: UserDefaults = .standard) {
        let version = defaults.integer(forKey: key)
        guard version < current else { return }
        if version < 2 { upgradeToTwo(context: context, store: store) }
        defaults.set(current, forKey: key)
    }

    /// 1.0 → 2.0: eight-tier ranking ladder and new muscle groups.
    static func upgradeToTwo(context: ModelContext, store: TrainingStore) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        // Custom tiers set in 1.0 had four values; keep them and fill in the new tiers.
        for exercise in exercises {
            if let custom = exercise.customThresholds, custom.count == 4 {
                exercise.customThresholds = RankingStandard.upgradeLegacy(custom)
            }
        }

        // Logged exercises keep a copy of their muscles; refresh it so traps, adductors and
        // abductors show up in history. Custom exercises are left as the user made them.
        let entries = (try? context.fetch(FetchDescriptor<ExerciseSession>())) ?? []
        for entry in entries {
            if let exercise = entry.exercise, !exercise.isCustom {
                entry.primaryMusclesRaw = exercise.primaryMusclesRaw
                entry.equipmentRaw = exercise.equipmentRaw
            }
        }
        try? context.save()

        // Rank snapshots from 1.0 used the five-tier scale, so regenerate them from workouts.
        store.refresh(context)
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        if !store.history.isEmpty {
            RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profile?.tierScale ?? 1)
        }
    }
}
