import SwiftData
import XCTest
@testable import PRIME

@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var store: TrainingStore!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try PrimeStore.makeContainer(inMemory: true)
        defaults = UserDefaults(suiteName: "prime-tests-\(UUID().uuidString)")
        try CatalogueService.seedIfNeeded(context: container.mainContext, defaults: defaults, force: true)
        store = TrainingStore()
        store.refresh(container.mainContext)
    }

    private func exercise(_ slug: String) throws -> Exercise {
        let found = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.slug == slug })).first
        return try XCTUnwrap(found, "missing \(slug)")
    }

    private func allExercises() throws -> [Exercise] { try context.fetch(FetchDescriptor<Exercise>()) }

    private func makePlan(_ name: String, slugs: [String], sets: Int = 3) throws -> WorkoutPlan {
        let plan = WorkoutPlan(name: name)
        context.insert(plan)
        for (index, slug) in slugs.enumerated() {
            let entry = PlannedExercise(position: index, exercise: try exercise(slug), targetSets: sets, targetReps: 5)
            context.insert(entry)
            entry.plan = plan
        }
        try context.save()
        return plan
    }

    // MARK: Catalogue

    func testCatalogueSeedsEveryBundledExercise() throws {
        let catalogue = try CatalogueService.loadBundled()
        XCTAssertGreaterThanOrEqual(catalogue.exercises.count, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), catalogue.exercises.count)
        // Seeding again doesn't duplicate.
        try CatalogueService.seedIfNeeded(context: context, defaults: defaults, force: true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), catalogue.exercises.count)
    }

    func testCatalogueIsInternallyConsistent() throws {
        let catalogue = try CatalogueService.loadBundled()
        let slugs = Set(catalogue.exercises.map(\.slug))
        XCTAssertEqual(slugs.count, catalogue.exercises.count, "slugs must be unique")
        for entry in catalogue.exercises {
            XCTAssertFalse(entry.primary.isEmpty, entry.slug)
            XCTAssertTrue(entry.primary.allSatisfy { MuscleGroup(rawValue: $0) != nil }, entry.slug)
            XCTAssertNotNil(Equipment(rawValue: entry.equipment), entry.slug)
            XCTAssertTrue(entry.alternatives.allSatisfy(slugs.contains), entry.slug)
            let guide = try XCTUnwrap(entry.guide, "\(entry.slug) has no guide")
            XCTAssertFalse(guide.overview.isEmpty, entry.slug)
            XCTAssertFalse(guide.setup.isEmpty, entry.slug)
            XCTAssertGreaterThanOrEqual(guide.steps.count, 2, entry.slug)
            XCTAssertFalse(guide.form.isEmpty, entry.slug)
            XCTAssertFalse(guide.breathing.isEmpty, entry.slug)
            XCTAssertGreaterThanOrEqual(guide.mistakes.count, 2, entry.slug)
            XCTAssertTrue(guide.mistakes.allSatisfy { !$0.what.isEmpty && !$0.why.isEmpty && !$0.fix.isEmpty }, entry.slug)
            XCTAssertFalse(guide.safety.isEmpty, entry.slug)
            XCTAssertFalse(guide.easier.isEmpty || guide.harder.isEmpty, entry.slug)
            if let ranking = entry.ranking, ranking.method != RankingMethod.unranked.rawValue {
                XCTAssertTrue(RankingStandard.isValid(ranking.thresholds), entry.slug)
                XCTAssertNotEqual(guide.tracking, .time, "\(entry.slug): timed holds aren't ranked")
            }
        }
        for muscle in MuscleGroup.allCases {
            XCTAssertTrue(catalogue.exercises.contains { $0.primary.contains(muscle.rawValue) }, "\(muscle) has no exercises")
        }
        for equipment in Equipment.allCases {
            XCTAssertTrue(catalogue.exercises.contains { $0.equipment == equipment.rawValue }, "\(equipment) has no exercises")
        }
        for template in WorkoutTemplate.all {
            for item in template.items { XCTAssertTrue(slugs.contains(item.slug), "\(template.id) uses unknown \(item.slug)") }
        }
        XCTAssertTrue(ExerciseLibrary.shared.isTimed("plank"))
        XCTAssertFalse(ExerciseLibrary.shared.isTimed("barbell-bench-press"))
    }

    func testFavouritesSurviveCatalogueRefresh() throws {
        let bench = try exercise("barbell-bench-press")
        bench.isFavourite = true
        bench.customThresholds = [0.5, 0.9, 1.2, 1.4, 1.6, 1.8, 2.0]
        try context.save()
        try CatalogueService.seedIfNeeded(context: context, defaults: defaults, force: true)
        XCTAssertTrue(try exercise("barbell-bench-press").isFavourite)
        XCTAssertEqual(try exercise("barbell-bench-press").customThresholds, [0.5, 0.9, 1.2, 1.4, 1.6, 1.8, 2.0])
    }

    // MARK: Workout planning

    func testWeekHasSevenDaysAndMovingSwaps() throws {
        let days = ScheduleService.ensureWeek(context: context)
        XCTAssertEqual(days.map(\.weekday), Array(0..<7))
        XCTAssertEqual(ScheduleService.ensureWeek(context: context).count, 7)
        let push = try makePlan("Push", slugs: ["barbell-bench-press"])
        let legs = try makePlan("Legs", slugs: ["barbell-back-squat"])
        ScheduleService.assign(push, to: days[0], context: context)
        ScheduleService.assign(legs, to: days[2], context: context)
        ScheduleService.setRest(days[1], context: context)
        ScheduleService.move(from: days[0], to: days[2], context: context)
        XCTAssertEqual(days[0].plan?.name, "Legs")
        XCTAssertEqual(days[2].plan?.name, "Push")
        ScheduleService.move(from: days[2], to: days[1], context: context)
        XCTAssertEqual(days[1].plan?.name, "Push")
        XCTAssertTrue(days[2].isRest)
        XCTAssertEqual(days[1].state, .training)
    }

    func testDuplicateAndDeleteRoutine() throws {
        let plan = try makePlan("Upper", slugs: ["barbell-bench-press", "barbell-bent-over-row"])
        let days = ScheduleService.ensureWeek(context: context)
        ScheduleService.assign(plan, to: days[3], context: context)
        let copy = ScheduleService.duplicate(plan, context: context)
        XCTAssertEqual(copy.name, "Upper copy")
        XCTAssertEqual(copy.sortedEntries.map(\.exerciseSlug), ["barbell-bench-press", "barbell-bent-over-row"])
        XCTAssertTrue(copy.days.isEmpty)
        ScheduleService.delete(plan, context: context)
        XCTAssertNil(days[3].plan)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedExercise>()), 2)
    }

    func testPresetFollowsTheChosenStartDay() throws {
        let ppl = try XCTUnwrap(SplitPreset.all.first { $0.id == "ppl" })
        let plans = ScheduleService.apply(ppl, start: 2, mode: .replace, exercises: try allExercises(), restSeconds: 90, context: context)
        XCTAssertEqual(Set(plans.map(\.name)), ["Push", "Pull", "Legs"])
        XCTAssertTrue(plans.allSatisfy { !$0.entries.isEmpty && $0.sourceTemplateID != nil })
        let days = ScheduleService.ensureWeek(context: context)
        // Wednesday start: Wed Push, Thu Pull, Fri Legs, Sat rest, Sun Push, Mon Pull, Tue Legs.
        XCTAssertEqual(days.map { $0.isRest ? "Rest" : ($0.plan?.name ?? "-") }, ["Pull", "Legs", "Push", "Pull", "Legs", "Rest", "Push"])
    }

    func testReapplyingAPresetReusesItsRoutinesAndKeepsEdits() throws {
        let ppl = try XCTUnwrap(SplitPreset.all.first { $0.id == "ppl" })
        let first = ScheduleService.apply(ppl, start: 0, mode: .replace, exercises: try allExercises(), restSeconds: 90, context: context)
        let push = try XCTUnwrap(first.first { $0.name == "Push" })
        push.name = "My Push"
        try context.save()
        _ = ScheduleService.apply(ppl, start: 3, mode: .replace, exercises: try allExercises(), restSeconds: 90, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 3, "applied routines are reused, not duplicated")
        XCTAssertEqual(ScheduleService.ensureWeek(context: context)[3].plan?.name, "My Push", "user edits to the copy survive")
    }

    func testFillEmptyLeavesPlannedDaysAlone() throws {
        let days = ScheduleService.ensureWeek(context: context)
        let mine = try makePlan("Mine", slugs: ["barbell-bench-press"])
        ScheduleService.assign(mine, to: days[0], context: context)
        let ul = try XCTUnwrap(SplitPreset.all.first { $0.id == "ul4" })
        _ = ScheduleService.apply(ul, start: 0, mode: .fillEmpty, exercises: try allExercises(), restSeconds: 90, context: context)
        XCTAssertEqual(days[0].plan?.name, "Mine")
        XCTAssertEqual(days[1].plan?.name, "Lower Body")
    }

    func testPausedRestKeepsItsRemainingTime() throws {
        let session = WorkoutService.start(plan: nil, context: context, history: store.history)
        let now = Date()
        WorkoutService.startRest(session, seconds: 90, label: "Bench", notify: false, now: now)
        WorkoutService.pauseRest(session, now: now.addingTimeInterval(30))
        XCTAssertNil(session.restEndsAt)
        XCTAssertEqual(session.restPausedRemaining, 60)
        let later = now.addingTimeInterval(300)
        WorkoutService.resumeRest(session, notify: false, now: later)
        XCTAssertEqual(session.restEndsAt, later.addingTimeInterval(60))
        XCTAssertNil(session.restPausedRemaining)
    }

    func testTimedExerciseLogsSecondsWithoutVolume() throws {
        let session = WorkoutService.start(plan: nil, context: context, history: store.history)
        let item = WorkoutService.addExercise(try exercise("plank"), to: session, restSeconds: 60, context: context, history: store.history)
        let set = item.sortedSets[0]
        set.reps = 75
        XCTAssertNoThrow(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context))
        let summary = try WorkoutService.finish(session, context: context, store: store, profile: nil, exercises: try allExercises())
        XCTAssertEqual(summary.volumeKg, 0)
        XCTAssertEqual(summary.repCount, 0, "seconds aren't reps")
        XCTAssertTrue(summary.rankChanges.isEmpty)
        XCTAssertEqual(store.history.samples(for: "plank").first?.isTimed, true)
    }

    // MARK: Workout tracking

    func testStartingFromAPlanCreatesSets() throws {
        let plan = try makePlan("Push", slugs: ["barbell-bench-press", "overhead-press"], sets: 4)
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        XCTAssertEqual(session.sortedExercises.map(\.exerciseSlug), ["barbell-bench-press", "overhead-press"])
        XCTAssertEqual(session.sortedExercises.first?.sets.count, 4)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.completion, 0)
    }

    func testInvalidSetsCannotBeCompleted() throws {
        let plan = try makePlan("Push", slugs: ["barbell-bench-press"])
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        let item = session.sortedExercises[0]
        let set = item.sortedSets[0]
        XCTAssertThrowsError(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context))
        set.reps = 5
        XCTAssertThrowsError(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context), "a barbell set needs a weight")
        set.weightKg = 0
        XCTAssertThrowsError(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context))
        set.weightKg = 100
        set.reps = 0
        XCTAssertThrowsError(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context))
        XCTAssertFalse(set.isCompleted)
    }

    func testBodyweightSetsDontNeedLoad() throws {
        let session = WorkoutService.start(plan: nil, context: context, history: store.history)
        let item = WorkoutService.addExercise(try exercise("pull-up"), to: session, restSeconds: 90, context: context, history: store.history)
        let set = item.sortedSets[0]
        set.reps = 8
        XCTAssertNoThrow(try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context))
        XCTAssertTrue(set.isCompleted)
    }

    func testEmptyWorkoutCannotBeFinished() throws {
        let session = WorkoutService.start(plan: nil, context: context, history: store.history)
        XCTAssertThrowsError(try WorkoutService.finish(session, context: context, store: store, profile: nil, exercises: try allExercises())) { error in
            XCTAssertEqual(error as? WorkoutError, .noCompletedSets)
        }
        XCTAssertTrue(session.isActive)
    }

    func testFinishingSavesHistoryRecordsAndRanks() throws {
        DataService.logBodyweight(80, on: Date().addingTimeInterval(-86_400 * 10), context: context)
        store.refresh(context)
        let plan = try makePlan("Push", slugs: ["barbell-bench-press"])

        // First workout sets the baseline: no records, but a first rank.
        let first = WorkoutService.start(plan: plan, context: context, history: store.history, now: Date().addingTimeInterval(-86_400 * 3))
        let firstItem = first.sortedExercises[0]
        for set in firstItem.sortedSets.prefix(2) {
            set.weightKg = 90
            set.reps = 5
            _ = try WorkoutService.complete(set, in: firstItem, session: first, history: store.history, context: context)
        }
        let firstSummary = try WorkoutService.finish(first, context: context, store: store, profile: nil, exercises: try allExercises())
        XCTAssertTrue(firstSummary.records.isEmpty)
        XCTAssertEqual(firstSummary.setCount, 2)
        XCTAssertEqual(firstSummary.volumeKg, 900, accuracy: 0.001)
        XCTAssertEqual(firstSummary.rankChanges.first?.to, .silver) // 90 × 1.1667 / 80 = 1.31
        XCTAssertEqual(firstItem.sets.filter { !$0.isDeleted }.count, 2, "unfinished sets are removed")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 2)
        XCTAssertEqual(store.history.sessions.count, 1)

        // Second workout beats it.
        let second = WorkoutService.start(plan: plan, context: context, history: store.history)
        let item = second.sortedExercises[0]
        XCTAssertEqual(WorkoutService.suggestion(for: item.sortedSets[0], in: item, history: store.history).weightKg, 90, "previous performance is offered")
        let set = item.sortedSets[0]
        set.weightKg = 100
        set.reps = 5
        let live = try WorkoutService.complete(set, in: item, session: second, history: store.history, context: context)
        XCTAssertTrue(live.contains(.heaviestWeight))
        XCTAssertTrue(live.contains(.bestOneRepMax))
        let summary = try WorkoutService.finish(second, context: context, store: store, profile: nil, exercises: try allExercises())
        XCTAssertTrue(summary.records.contains { $0.achievement.kind == .heaviestWeight })
        XCTAssertEqual(summary.rankChanges.first?.to, .gold) // 116.7 / 80 = 1.46
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PerformanceRanking>()), 2)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
    }

    func testDeletingAWorkoutRebuildsRecords() throws {
        let plan = try makePlan("Legs", slugs: ["barbell-back-squat"], sets: 1)
        for weight in [100.0, 120.0] {
            let session = WorkoutService.start(plan: plan, context: context, history: store.history)
            let item = session.sortedExercises[0]
            item.sortedSets[0].weightKg = weight
            item.sortedSets[0].reps = 3
            _ = try WorkoutService.complete(item.sortedSets[0], in: item, session: session, history: store.history, context: context)
            _ = try WorkoutService.finish(session, context: context, store: store, profile: nil, exercises: try allExercises())
        }
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
        let completed = SessionStatus.completed.rawValue
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == completed }, sortBy: [SortDescriptor(\.startedAt)]))
        WorkoutService.deleteCompleted(sessions[1], context: context, store: store, profile: nil, exercises: try allExercises())
        XCTAssertEqual(store.history.sessions.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0, "the only record came from the deleted workout")
    }

    func testDeletedExerciseKeepsLoggedHistory() throws {
        let custom = Exercise(slug: "custom-test", name: "My Test Press")
        custom.isCustom = true
        custom.primaryMuscles = [.shoulders]
        custom.equipment = .barbell
        custom.rankingMethod = .unranked
        context.insert(custom)
        let plan = WorkoutPlan(name: "Shoulders")
        context.insert(plan)
        let entry = PlannedExercise(position: 0, exercise: custom)
        context.insert(entry)
        entry.plan = plan
        try context.save()

        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        let item = session.sortedExercises[0]
        item.sortedSets[0].weightKg = 40
        item.sortedSets[0].reps = 10
        _ = try WorkoutService.complete(item.sortedSets[0], in: item, session: session, history: store.history, context: context)
        _ = try WorkoutService.finish(session, context: context, store: store, profile: nil, exercises: try allExercises())

        context.delete(custom)
        try context.save()
        store.refresh(context)
        XCTAssertEqual(store.history.exerciseName(for: "custom-test"), "My Test Press")
        XCTAssertEqual(store.history.samples(for: "custom-test").count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedExercise>()), 0, "the deleted exercise leaves the routine")
        XCTAssertEqual(store.history.samples.first?.primaryMuscles, [.shoulders])
    }

    func testReplacingAnExerciseKeepsItsPlace() throws {
        let plan = try makePlan("Push", slugs: ["barbell-bench-press", "overhead-press"])
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        let first = session.sortedExercises[0]
        first.sortedSets[0].weightKg = 60
        WorkoutService.replace(first, with: try exercise("dumbbell-bench-press"), context: context)
        XCTAssertEqual(session.sortedExercises.map(\.exerciseSlug), ["dumbbell-bench-press", "overhead-press"])
        XCTAssertNil(first.sortedSets[0].weightKg, "old values don't carry over to a different exercise")
    }

    func testRestTimerIsStoredOnTheSession() throws {
        let session = WorkoutService.start(plan: nil, context: context, history: store.history)
        let now = Date()
        WorkoutService.startRest(session, seconds: 90, label: "Bench", notify: false, now: now)
        XCTAssertEqual(session.restEndsAt, now.addingTimeInterval(90))
        WorkoutService.adjustRest(session, by: 15, notify: false, now: now)
        XCTAssertEqual(session.restEndsAt, now.addingTimeInterval(105))
        WorkoutService.adjustRest(session, by: -500, notify: false, now: now)
        XCTAssertEqual(session.restEndsAt, now.addingTimeInterval(1), "never goes into the past")
        WorkoutService.endRest(session)
        XCTAssertNil(session.restEndsAt)
    }

    func testCSVExport() throws {
        let plan = try makePlan("Push", slugs: ["barbell-bench-press"], sets: 1)
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        let item = session.sortedExercises[0]
        item.sortedSets[0].weightKg = WeightUnit.lb.toKilograms(135)
        item.sortedSets[0].reps = 8
        _ = try WorkoutService.complete(item.sortedSets[0], in: item, session: session, history: store.history, context: context)
        _ = try WorkoutService.finish(session, context: context, store: store, profile: nil, exercises: try allExercises())
        let url = try DataService.exportCSV(history: store.history, unit: .lb)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("Date,Workout,Exercise,Set,Weight (lb)"))
        XCTAssertTrue(text.contains("Barbell Bench Press,1,135,8"))
    }
}

/// Uses a real file so the store can be closed and reopened like an app restart.
@MainActor
final class RestartTests: XCTestCase {
    func testActiveWorkoutSurvivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prime-restart-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "prime-restart-\(UUID().uuidString)"))

        var sessionID: UUID?
        do {
            let container = try PrimeStore.makeContainer(url: url)
            let context = container.mainContext
            try CatalogueService.seedIfNeeded(context: context, defaults: defaults, force: true)
            let squat = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.slug == "barbell-back-squat" })).first)
            let session = WorkoutService.start(plan: nil, context: context, history: .empty)
            let item = WorkoutService.addExercise(squat, to: session, restSeconds: 120, context: context, history: .empty)
            item.sortedSets[0].weightKg = 140
            item.sortedSets[0].reps = 5
            _ = try WorkoutService.complete(item.sortedSets[0], in: item, session: session, history: .empty, context: context)
            WorkoutService.startRest(session, seconds: 120, label: "Squat", notify: false)
            try context.save()
            sessionID = session.uuid
        }

        let reopened = try PrimeStore.makeContainer(url: url)
        let restored = try XCTUnwrap(WorkoutService.activeSession(in: reopened.mainContext))
        XCTAssertEqual(restored.uuid, sessionID)
        XCTAssertEqual(restored.completedSets.count, 1)
        XCTAssertEqual(restored.completedSets.first?.weightKg, 140)
        XCTAssertNotNil(restored.restEndsAt, "the rest timer resumes after a relaunch")
    }
}

/// Builds a store with the frozen 1.0 schema, then opens it with the current app schema.
@MainActor
final class MigrationTests: XCTestCase {
    func testVersionOneStoreMigratesWithoutLosingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prime-v1-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) }
        }
        let sessionID = UUID()
        do {
            let schema = Schema(versionedSchema: PrimeSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = container.mainContext
            let profile = PrimeSchemaV1.UserProfile()
            profile.name = "Jude"
            profile.tierScale = 0.9
            context.insert(profile)
            let bodyweight = PrimeSchemaV1.BodyweightEntry()
            bodyweight.weightKg = 81
            context.insert(bodyweight)
            let bench = PrimeSchemaV1.Exercise(slug: "barbell-bench-press", name: "Barbell Bench Press")
            bench.customThresholds = [0.5, 0.9, 1.2, 1.6]
            bench.isFavourite = true
            context.insert(bench)
            let session = PrimeSchemaV1.WorkoutSession(name: "Push")
            session.uuid = sessionID
            session.statusRaw = "completed"
            session.endedAt = Date()
            context.insert(session)
            let entry = PrimeSchemaV1.ExerciseSession()
            entry.exerciseSlug = "barbell-bench-press"
            entry.exerciseName = "Barbell Bench Press"
            entry.primaryMusclesRaw = ["chest"]
            entry.exercise = bench
            entry.session = session
            context.insert(entry)
            let set = PrimeSchemaV1.ExerciseSet()
            set.weightKg = 100
            set.reps = 5
            set.isCompleted = true
            set.completedAt = Date()
            set.exerciseSession = entry
            context.insert(set)
            let ranking = PrimeSchemaV1.PerformanceRanking()
            ranking.exerciseSlug = "barbell-bench-press"
            ranking.tierRaw = 2
            ranking.sessionID = sessionID
            context.insert(ranking)
            try context.save()
        }

        let container = try PrimeStore.makeContainer(url: url)
        let context = container.mainContext
        let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(profile.name, "Jude")
        XCTAssertEqual(profile.tierScale, 0.9)
        XCTAssertTrue(profile.hapticsEnabled, "new settings get their defaults")
        XCTAssertEqual(profile.animationLevelRaw, "full")
        XCTAssertTrue(profile.dashboardOrder.isEmpty)
        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.uuid, sessionID)
        XCTAssertNil(session.readiness)
        XCTAssertNil(session.restPausedRemaining)
        XCTAssertEqual(session.completedSets.first?.weightKg, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyweightEntry>()), 1)
        let ranking = try XCTUnwrap(try context.fetch(FetchDescriptor<PerformanceRanking>()).first)
        XCTAssertFalse(ranking.isSubmitted, "1.0 ranks came from workouts")
        let bench = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertTrue(bench.isFavourite)

        // The data step then upgrades four-value custom tiers to the seven-threshold ladder.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "prime-migrate-\(UUID().uuidString)"))
        try CatalogueService.seedIfNeeded(context: context, defaults: defaults)
        let store = TrainingStore()
        store.refresh(context)
        UpgradeService.runIfNeeded(context: context, store: store, defaults: defaults)
        XCTAssertEqual(bench.customThresholds?.count, RankTier.thresholdCount)
        XCTAssertEqual(Array(bench.customThresholds?.prefix(3) ?? []), [0.5, 0.9, 1.2])
        XCTAssertEqual(store.history.sessions.count, 1)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Exercise>()), 100)
    }
}
