import XCTest
@testable import PRIME

/// Fixed dates so week maths don't depend on when the tests run.
private enum Dates {
    static let calendar = Calendar.prime

    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Wednesday 11 November 2026.
    static let now = day(2026, 11, 11, hour: 21)
}

private func sample(_ session: UUID, _ date: Date, slug: String = "bench", weight: Double, reps: Int,
                    muscles: [MuscleGroup] = [.chest], index: Int = 0) -> SetSample {
    SetSample(sessionID: session, date: date, exerciseSlug: slug, exerciseName: slug.capitalized, equipment: .barbell,
              primaryMuscles: muscles, weightKg: weight, reps: reps, bodyweightKg: 80, setIndex: index)
}

final class AnalyticsTests: XCTestCase {
    func testTotalVolumeIgnoresBodyweightOnlySets() {
        let id = UUID()
        let sets = [sample(id, Dates.now, weight: 100, reps: 5), sample(id, Dates.now, weight: 0, reps: 15), sample(id, Dates.now, weight: 60, reps: 10)]
        XCTAssertEqual(Analytics.totalVolume(sets), 1100)
    }

    func testWeeklyBucketsIncludeEmptyWeeks() {
        let a = UUID(), b = UUID()
        let sets = [sample(a, Dates.day(2026, 10, 20), weight: 100, reps: 5), sample(b, Dates.day(2026, 11, 10), weight: 50, reps: 10)]
        let interval = DateInterval(start: Dates.day(2026, 10, 19, hour: 0), end: Dates.now)
        let buckets = Analytics.volume(sets, by: .week, in: interval)
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(buckets.map(\.value), [500, 0, 0, 500])
    }

    func testMonthlyBuckets() {
        let sets = [sample(UUID(), Dates.day(2026, 9, 5), weight: 100, reps: 1), sample(UUID(), Dates.day(2026, 11, 2), weight: 100, reps: 2)]
        let interval = DateInterval(start: Dates.day(2026, 9, 1, hour: 0), end: Dates.now)
        XCTAssertEqual(Analytics.volume(sets, by: .month, in: interval).map(\.value), [100, 0, 200])
    }

    func testDailyVolumeForAWeek() {
        let sets = [sample(UUID(), Dates.day(2026, 11, 9), weight: 100, reps: 5), sample(UUID(), Dates.day(2026, 11, 11), weight: 20, reps: 10)]
        let days = Analytics.dailyVolume(sets, weekContaining: Dates.now)
        XCTAssertEqual(days, [500, 0, 200, 0, 0, 0, 0])
    }

    func testVolumeAndSetsByMuscleUsePrimaryMuscles() {
        let id = UUID()
        let sets = [
            sample(id, Dates.now, weight: 100, reps: 5, muscles: [.chest]),
            sample(id, Dates.now, slug: "squat", weight: 120, reps: 5, muscles: [.quadriceps, .glutes]),
        ]
        let volume = Analytics.volumeByMuscle(sets)
        XCTAssertEqual(volume[.chest], 500)
        XCTAssertEqual(volume[.quadriceps], 600)
        XCTAssertEqual(volume[.glutes], 600)
        XCTAssertNil(volume[.triceps])
        XCTAssertEqual(Analytics.setsByMuscle(sets)[.glutes], 1)
    }

    func testVolumeByExerciseSorted() {
        let id = UUID()
        let rows = Analytics.volumeByExercise([
            sample(id, Dates.now, slug: "curl", weight: 20, reps: 10),
            sample(id, Dates.now, slug: "squat", weight: 100, reps: 5),
        ])
        XCTAssertEqual(rows.map(\.slug), ["squat", "curl"])
    }

    func testOneRepMaxProgressionTakesBestSetPerSession() {
        let first = UUID(), second = UUID()
        let sets = [
            sample(first, Dates.day(2026, 11, 2), weight: 100, reps: 5),
            sample(first, Dates.day(2026, 11, 2), weight: 105, reps: 3),
            sample(second, Dates.day(2026, 11, 9), weight: 110, reps: 3),
        ]
        let points = Analytics.oneRepMaxProgression(sets)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].value, 116.667, accuracy: 0.001)
        XCTAssertEqual(points[1].value, 121, accuracy: 0.001)
        XCTAssertEqual(Analytics.weightProgression(sets).map(\.value), [105, 110])
    }

    func testWeekStreakDoesNotBreakDuringCurrentWeek() {
        let dates = [
            Dates.day(2026, 11, 9),                          // this week: 1 (goal 2, still in progress)
            Dates.day(2026, 11, 3), Dates.day(2026, 11, 5),  // last week: 2
            Dates.day(2026, 10, 27), Dates.day(2026, 10, 29),// two weeks ago: 2
            Dates.day(2026, 10, 21),                         // three weeks ago: 1 → breaks
        ]
        XCTAssertEqual(Analytics.weekStreak(sessionDates: dates, weeklyGoal: 2, now: Dates.now), 2)
        XCTAssertEqual(Analytics.weekStreak(sessionDates: dates + [Dates.day(2026, 11, 10)], weeklyGoal: 2, now: Dates.now), 3)
        XCTAssertEqual(Analytics.weekStreak(sessionDates: [], weeklyGoal: 2, now: Dates.now), 0)
    }

    func testBestWeekStreak() {
        let dates = [Dates.day(2026, 9, 1), Dates.day(2026, 9, 8), Dates.day(2026, 9, 15), Dates.day(2026, 10, 13), Dates.day(2026, 10, 20)]
        XCTAssertEqual(Analytics.bestWeekStreak(sessionDates: dates, weeklyGoal: 1), 3)
    }

    func testRangesProduceSensibleIntervals() {
        let interval = AnalyticsRange.month.interval(now: Dates.now, earliest: nil)
        XCTAssertEqual(interval.end, Dates.now)
        XCTAssertLessThan(interval.start, Dates.now)
        let all = AnalyticsRange.all.interval(now: Dates.now, earliest: Dates.day(2025, 1, 1))
        XCTAssertLessThanOrEqual(all.start, Dates.day(2025, 1, 1))
    }
}

final class PersonalRecordTests: XCTestCase {
    private func history() -> RecordSnapshot {
        let id = UUID()
        return RecordSnapshot.from([sample(id, Dates.day(2026, 11, 2), weight: 100, reps: 5), sample(id, Dates.day(2026, 11, 2), weight: 100, reps: 5, index: 1)])
    }

    func testFirstEverSessionSetsABaselineNotARecord() {
        XCTAssertTrue(PRDetector.sessionRecords(sets: [(100, 5)], against: .empty).isEmpty)
        XCTAssertTrue(PRDetector.recordsBeaten(weightKg: 200, reps: 1, against: .empty).isEmpty)
    }

    func testSessionRecords() {
        let records = PRDetector.sessionRecords(sets: [(105, 3), (100, 6)], against: history())
        let kinds = Set(records.map(\.kind))
        XCTAssertEqual(kinds, [.heaviestWeight, .bestOneRepMax, .bestSetVolume, .mostRepsAtWeight])
        XCTAssertEqual(records.first { $0.kind == .bestOneRepMax }?.value ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(records.first { $0.kind == .mostRepsAtWeight }?.previous, 5)
        XCTAssertFalse(kinds.contains(.bestSessionVolume)) // 915 < 1000
    }

    func testEqualPerformanceIsNotARecord() {
        XCTAssertTrue(PRDetector.sessionRecords(sets: [(100, 5), (100, 5)], against: history()).isEmpty)
        XCTAssertTrue(PRDetector.recordsBeaten(weightKg: 100, reps: 5, against: history()).isEmpty)
    }

    func testLiveRecordDetection() {
        XCTAssertEqual(Set(PRDetector.recordsBeaten(weightKg: 100, reps: 6, against: history())), [.bestOneRepMax, .bestSetVolume, .mostRepsAtWeight])
        XCTAssertTrue(PRDetector.recordsBeaten(weightKg: 90, reps: 5, against: history()).isEmpty)
    }

    func testRepRecordsTable() {
        let id = UUID()
        let table = RepRecords.table([
            sample(id, Dates.now, weight: 100, reps: 5),
            sample(id, Dates.now, weight: 100, reps: 7),
            sample(id, Dates.now, weight: 80, reps: 10),
        ])
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table[0].weightKg, 100)
        XCTAssertEqual(table[0].reps, 7)
    }

    func testBodyweightNearestToDate() {
        let history = TrainingHistory(samples: [], sessions: [], bodyweights: [
            BodyweightPoint(date: Dates.day(2026, 10, 1), weightKg: 82),
            BodyweightPoint(date: Dates.day(2026, 11, 1), weightKg: 80),
        ])
        XCTAssertEqual(history.bodyweight(on: Dates.day(2026, 10, 15)), 82)
        XCTAssertEqual(history.bodyweight(on: Dates.now), 80)
        XCTAssertEqual(history.bodyweight(on: Dates.day(2026, 9, 1)), 82) // before any entry: earliest
        XCTAssertNil(TrainingHistory.empty.bodyweight(on: Dates.now))
    }
}

private struct FakeExercise: ExerciseDescribing {
    var displayName: String
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup] = []
    var equipment: Equipment
    var mechanic: Mechanic = .compound
    var difficulty: Difficulty = .beginner
    var favourite: Bool = false
}

final class ExerciseFilterTests: XCTestCase {
    private let items = [
        FakeExercise(displayName: "Barbell Bench Press", primaryMuscles: [.chest], secondaryMuscles: [.triceps], equipment: .barbell),
        FakeExercise(displayName: "Triceps Dip", primaryMuscles: [.triceps], secondaryMuscles: [.chest], equipment: .bodyweight),
        FakeExercise(displayName: "Lateral Raise", primaryMuscles: [.shoulders], equipment: .dumbbell, mechanic: .isolation, favourite: true),
        FakeExercise(displayName: "Leg Press", primaryMuscles: [.quadriceps], equipment: .machine),
    ]

    func testSearchMatchesNamesMusclesAndEquipment() {
        XCTAssertEqual(ExerciseFilter(query: "bench").apply(to: items).map(\.displayName), ["Barbell Bench Press"])
        XCTAssertEqual(ExerciseFilter(query: "quads").apply(to: items).map(\.displayName), ["Leg Press"])
        XCTAssertEqual(ExerciseFilter(query: "DUMBBELL").apply(to: items).map(\.displayName), ["Lateral Raise"])
        XCTAssertEqual(ExerciseFilter(query: "press machine").apply(to: items).map(\.displayName), ["Leg Press"])
        XCTAssertTrue(ExerciseFilter(query: "zzz").apply(to: items).isEmpty)
    }

    func testMuscleFilterUsesPrimaryUnlessAskedOtherwise() {
        var filter = ExerciseFilter(muscles: [.chest])
        XCTAssertEqual(filter.apply(to: items).map(\.displayName), ["Barbell Bench Press"])
        filter.includeSecondary = true
        XCTAssertEqual(Set(filter.apply(to: items).map(\.displayName)), ["Barbell Bench Press", "Triceps Dip"])
    }

    func testEquipmentMechanicAndFavourites() {
        XCTAssertEqual(ExerciseFilter(equipment: [.machine, .bodyweight]).apply(to: items).count, 2)
        XCTAssertEqual(ExerciseFilter(mechanic: .isolation).apply(to: items).map(\.displayName), ["Lateral Raise"])
        XCTAssertEqual(ExerciseFilter(favouritesOnly: true).apply(to: items).map(\.displayName), ["Lateral Raise"])
        XCTAssertEqual(ExerciseFilter(favouritesOnly: true).activeFilterCount, 1)
    }

    func testNameStartMatchesSortFirst() {
        let results = ExerciseFilter(query: "press").apply(to: items).map(\.displayName)
        XCTAssertEqual(results, ["Barbell Bench Press", "Leg Press"])
        let triceps = ExerciseFilter(query: "tri").apply(to: items).map(\.displayName)
        XCTAssertEqual(triceps.first, "Triceps Dip")
    }
}

final class OverhaulDomainTests: XCTestCase {
    func testRepsTotalSkipsTimedHolds() {
        let id = UUID()
        let hold = SetSample(sessionID: id, date: Dates.now, exerciseSlug: "plank", exerciseName: "Plank", equipment: .bodyweight,
                             primaryMuscles: [.abdominals], weightKg: 0, reps: 60, isTimed: true)
        let sets = [sample(id, Dates.now, weight: 100, reps: 5), hold]
        XCTAssertEqual(Analytics.totalReps(sets), 5)
        XCTAssertEqual(Analytics.totalVolume(sets), 500)
    }

    func testMuscleSetsCountPrimaryOnlySoNothingIsDoubleCounted() {
        let id = UUID()
        let sets = [
            sample(id, Dates.day(2026, 11, 2), weight: 100, reps: 5, muscles: [.chest]),
            sample(id, Dates.day(2026, 11, 9), weight: 100, reps: 5, muscles: [.chest]),
            sample(id, Dates.day(2026, 11, 9), slug: "dip", weight: 0, reps: 10, muscles: [.triceps]),
        ]
        let interval = DateInterval(start: Dates.day(2026, 11, 2, hour: 0), end: Dates.now)
        XCTAssertEqual(Analytics.sets(for: .chest, in: sets, by: .week, interval: interval).map(\.value), [1, 1])
        XCTAssertEqual(Analytics.exercises(for: .chest, in: sets).map(\.sets), [2])
        XCTAssertTrue(Analytics.exercises(for: .shoulders, in: sets).isEmpty)
    }

    func testRangesHaveExpectedLabels() {
        XCTAssertEqual(AnalyticsRange.allCases.map(\.label), ["7D", "30D", "90D", "6M", "1Y", "All"])
        let week = AnalyticsRange.week.interval(now: Dates.now, earliest: nil)
        XCTAssertEqual(Calendar.prime.dateComponents([.day], from: week.start, to: week.end).day, 6)
    }

    func testTimedRecordsTrackLongestHold() {
        let id = UUID()
        let history = RecordSnapshot.from([
            SetSample(sessionID: id, date: Dates.day(2026, 11, 2), exerciseSlug: "plank", exerciseName: "Plank", equipment: .bodyweight,
                      primaryMuscles: [.abdominals], weightKg: 0, reps: 60, isTimed: true),
        ])
        XCTAssertEqual(history.longestHoldSeconds, 60)
        XCTAssertEqual(PRDetector.recordsBeaten(weightKg: 0, reps: 75, against: history, timed: true), [.longestHold])
        XCTAssertTrue(PRDetector.recordsBeaten(weightKg: 0, reps: 45, against: history, timed: true).isEmpty)
    }

    // MARK: Insights

    private func sessions(_ values: [(day: Int, weight: Double)], slug: String = "bench") -> [SetSample] {
        values.map { sample(UUID(), Dates.day(2026, 10, $0.day), slug: slug, weight: $0.weight, reps: 5) }
    }

    func testNewBestInsightComesFromRealData() {
        let samples = sessions([(1, 100), (8, 100), (15, 105)])
        let insights = InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: samples, isTimed: false, now: Dates.day(2026, 10, 16))
        XCTAssertTrue(insights.contains { $0.kind == .newBest })
        XCTAssertFalse(insights.contains { $0.kind == .plateau })
    }

    func testPlateauNeedsEnoughHistoryAndOffersAnOptionalSuggestion() {
        let samples = sessions([(1, 110), (8, 105), (15, 105), (22, 107.5)])
        let insights = InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: samples, isTimed: false, now: Dates.day(2026, 10, 23))
        let plateau = insights.first { $0.kind == .plateau }
        XCTAssertNotNil(plateau)
        XCTAssertTrue(plateau?.suggestion?.hasPrefix("If you want") ?? false)
        let short = InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: Array(samples.prefix(2)), isTimed: false, now: Dates.day(2026, 10, 9))
        XCTAssertFalse(short.contains { $0.kind == .plateau })
    }

    func testImprovingTrendOverFourSessions() {
        let samples = sessions([(1, 100), (8, 102.5), (15, 105), (22, 107.5)])
        let insights = InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: samples, isTimed: false, now: Dates.day(2026, 10, 23))
        XCTAssertTrue(insights.contains { $0.kind == .improving })
    }

    func testNotRecentOnlyForRegularExercises() {
        let samples = sessions([(1, 100), (3, 100), (5, 100)])
        let insights = InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: samples, isTimed: false, now: Dates.day(2026, 11, 5))
        XCTAssertEqual(insights.map(\.kind), [.notRecent])
        XCTAssertTrue(InsightEngine.exerciseInsights(slug: "bench", name: "Bench", samples: Array(samples.prefix(1)), isTimed: false, now: Dates.day(2026, 11, 5)).isEmpty)
    }

    func testMissedSessionsUseTheTimetable() {
        let insight = InsightEngine.missedSessionInsight(plannedWeekdays: [0, 2, 4], sessionDates: [Dates.day(2026, 11, 9)],
                                                         trackingSince: Dates.day(2026, 10, 1), now: Dates.now)
        XCTAssertNotNil(insight)
        XCTAssertNil(InsightEngine.missedSessionInsight(plannedWeekdays: [], sessionDates: [], trackingSince: Dates.day(2026, 10, 1), now: Dates.now))
    }

    // MARK: Badges

    func testBadgesNeverRewardVolume() {
        let badges = BadgeEngine.globalBadges(workouts: 12, routineWorkouts: 3, bestStreak: 5, recordCount: 2, peakTier: .gold)
        XCTAssertFalse(badges.contains { $0.title.lowercased().contains("volume") || $0.detail.lowercased().contains("volume") })
        XCTAssertTrue(badges.first { $0.id == "w10" }?.isEarned ?? false)
        XCTAssertFalse(badges.first { $0.id == "w50" }?.isEarned ?? true)
        XCTAssertTrue(badges.first { $0.id == "rank-\(RankTier.gold.rawValue)" }?.isEarned ?? false)
        XCTAssertFalse(badges.first { $0.id == "rank-\(RankTier.diamond.rawValue)" }?.isEarned ?? true)
        XCTAssertEqual(badges.first { $0.id == "w50" }?.progress ?? 0, 12.0 / 50, accuracy: 0.0001)
    }

    // MARK: Split presets

    func testPresetStartDayRotatesTheWeek() {
        let ppl = try! XCTUnwrap(SplitPreset.all.first { $0.id == "ppl" })
        // Starting Wednesday: Wed Push, Thu Pull, Fri Legs, Sat Rest, Sun Push, Mon Pull, Tue Legs.
        let layout = ppl.layout(startingOn: 2)
        XCTAssertEqual(layout[2] ?? nil, "push")
        XCTAssertEqual(layout[3] ?? nil, "pull")
        XCTAssertEqual(layout[4] ?? nil, "legs")
        XCTAssertEqual(layout[5] ?? "x", nil)
        XCTAssertEqual(layout[6] ?? nil, "push")
        XCTAssertEqual(layout[0] ?? nil, "pull")
        XCTAssertEqual(layout[1] ?? nil, "legs")
        XCTAssertEqual(layout.count, 7)
    }

    func testEveryPresetIsAWeekOfKnownTemplates() {
        for preset in SplitPreset.all {
            XCTAssertEqual(preset.cycle.count, 7, preset.id)
            XCTAssertGreaterThan(preset.sessionsPerWeek, 0, preset.id)
            for id in preset.templateIDs { XCTAssertNotNil(WorkoutTemplate.library[id], "\(preset.id) uses unknown template \(id)") }
        }
        XCTAssertEqual(Set(SplitPreset.all.map(\.id)).count, SplitPreset.all.count)
    }
}
