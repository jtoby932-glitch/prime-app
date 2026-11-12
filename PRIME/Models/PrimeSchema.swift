import Foundation
import SwiftData

/// Version 2: the current models (the top-level classes). Adds readiness, paused rest,
/// submitted rank entries, routine origins and app preferences. Every new field has a default,
/// so 1.0 stores migrate in place without losing anything.
enum PrimeSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, BodyweightEntry.self, Exercise.self, WorkoutPlan.self, PlannedExercise.self, WorkoutDay.self,
         WorkoutSession.self, ExerciseSession.self, ExerciseSet.self, PersonalRecord.self, PerformanceRanking.self]
    }
}

enum PrimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PrimeSchemaV1.self, PrimeSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PrimeSchemaV1.self, toVersion: PrimeSchemaV2.self)]
    }
}

enum PrimeStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // The default store lives in Application Support, which doesn't exist on a fresh install.
        if !inMemory {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        }
        let schema = Schema(versionedSchema: PrimeSchemaV2.self)
        // CloudKit stays off for now; sync is a future layer (it would need the unique constraints relaxed).
        let configuration = ModelConfiguration(
            inMemory ? "PRIME-\(UUID().uuidString)" : "PRIME",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: PrimeMigrationPlan.self, configurations: [configuration])
    }

    /// A store at a specific file, used by tests to simulate relaunches and upgrades.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PrimeSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: PrimeMigrationPlan.self, configurations: [configuration])
    }
}
