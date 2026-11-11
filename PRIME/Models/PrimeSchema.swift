import Foundation
import SwiftData

/// Version 1 of the store. Future changes add a `PrimeSchemaV2` and a migration stage below,
/// so existing workout history is carried forward instead of being wiped.
enum PrimeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            BodyweightEntry.self,
            Exercise.self,
            WorkoutPlan.self,
            PlannedExercise.self,
            WorkoutDay.self,
            WorkoutSession.self,
            ExerciseSession.self,
            ExerciseSet.self,
            PersonalRecord.self,
            PerformanceRanking.self,
        ]
    }
}

enum PrimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PrimeSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PrimeStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // The default store lives in Application Support, which doesn't exist on a fresh install.
        if !inMemory {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        }
        let schema = Schema(versionedSchema: PrimeSchemaV1.self)
        // CloudKit stays off for now; sync is a future layer (it would need the unique constraints relaxed).
        let configuration = ModelConfiguration(
            inMemory ? "PRIME-\(UUID().uuidString)" : "PRIME",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: PrimeMigrationPlan.self, configurations: [configuration])
    }

    /// A store at a specific file, used by tests to simulate the app being closed and reopened.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PrimeSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: PrimeMigrationPlan.self, configurations: [configuration])
    }
}
