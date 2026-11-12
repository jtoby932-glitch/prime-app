import XCTest
@testable import PRIME

final class StrengthMathTests: XCTestCase {
    func testEpleyEstimate() throws {
        let estimate = try XCTUnwrap(StrengthMath.estimatedOneRepMax(weight: 100, reps: 5))
        XCTAssertEqual(estimate, 116.6667, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(StrengthMath.estimatedOneRepMax(weight: 60, reps: 10)), 80, accuracy: 0.0001)
    }

    func testSingleRepIsTheOneRepMax() {
        XCTAssertEqual(StrengthMath.estimatedOneRepMax(weight: 140, reps: 1), 140)
    }

    func testInvalidInputGivesNoEstimate() {
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: 100, reps: 0))
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: 100, reps: -3))
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: 0, reps: 5))
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: -20, reps: 5))
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: .nan, reps: 5))
        XCTAssertNil(StrengthMath.estimatedOneRepMax(weight: .infinity, reps: 5))
    }

    func testRelativeStrength() throws {
        XCTAssertEqual(try XCTUnwrap(StrengthMath.relativeStrength(oneRepMax: 120, bodyweight: 80)), 1.5, accuracy: 0.0001)
    }

    func testRelativeStrengthNeedsBodyweight() {
        XCTAssertNil(StrengthMath.relativeStrength(oneRepMax: 120, bodyweight: nil))
        XCTAssertNil(StrengthMath.relativeStrength(oneRepMax: 120, bodyweight: 0))
        XCTAssertNil(StrengthMath.relativeStrength(oneRepMax: 120, bodyweight: -70))
    }

    func testBodyweightEquivalentReps() throws {
        XCTAssertEqual(StrengthMath.bodyweightEquivalentReps(bodyweight: nil, addedWeight: 0, reps: 12), 12)
        let weighted = try XCTUnwrap(StrengthMath.bodyweightEquivalentReps(bodyweight: 80, addedWeight: 10, reps: 8))
        XCTAssertEqual(weighted, 12.75, accuracy: 0.001)
        XCTAssertNil(StrengthMath.bodyweightEquivalentReps(bodyweight: nil, addedWeight: 10, reps: 8))
        XCTAssertNil(StrengthMath.bodyweightEquivalentReps(bodyweight: 80, addedWeight: 0, reps: 0))
    }

    func testSetVolume() {
        XCTAssertEqual(StrengthMath.setVolume(weight: 100, reps: 5), 500)
        XCTAssertEqual(StrengthMath.setVolume(weight: 0, reps: 20), 0)
        XCTAssertEqual(StrengthMath.setVolume(weight: nil, reps: 5), 0)
        XCTAssertEqual(StrengthMath.setVolume(weight: 50, reps: nil), 0)
        XCTAssertEqual(StrengthMath.setVolume(weight: 50, reps: 0), 0)
    }
}

final class RankingEngineTests: XCTestCase {
    let squat = RankingStandard(method: .relativeLoad, thresholds: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5], isCustom: false, note: "")
    let pullUp = RankingStandard(method: .repetitions, thresholds: [3, 6, 9, 12, 15, 18, 22], isCustom: false, note: "")

    func testEightTiersInOrder() {
        XCTAssertEqual(RankTier.allCases.map(\.name), ["Unranked", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Elite", "Master"])
        XCTAssertEqual(RankTier.ranked.count, RankTier.thresholdCount)
        XCTAssertNil(RankTier.master.next)
        XCTAssertEqual(RankTier.unranked.next, .bronze)
    }

    func testPlacementMidTier() {
        let placement = RankingEngine.placement(metric: 1.1, thresholds: squat.thresholds)
        XCTAssertEqual(placement.tier, .silver)
        XCTAssertEqual(placement.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(placement.score, 2.4, accuracy: 0.0001)
        XCTAssertEqual(placement.nextThreshold, 1.25)
    }

    func testThresholdIsInclusive() {
        XCTAssertEqual(RankingEngine.placement(metric: 1.0, thresholds: squat.thresholds).tier, .silver)
        XCTAssertEqual(RankingEngine.placement(metric: 0.9999, thresholds: squat.thresholds).tier, .bronze)
        XCTAssertEqual(RankingEngine.placement(metric: 2.0, thresholds: squat.thresholds).tier, .elite)
        XCTAssertEqual(RankingEngine.placement(metric: 2.5, thresholds: squat.thresholds).tier, .master)
    }

    func testUnrankedAndMasterEdges() {
        let below = RankingEngine.placement(metric: 0.5, thresholds: squat.thresholds)
        XCTAssertEqual(below.tier, .unranked)
        XCTAssertEqual(below.progress, 0.6667, accuracy: 0.001)
        XCTAssertEqual(below.nextThreshold, 0.75)
        let master = RankingEngine.placement(metric: 2.75, thresholds: squat.thresholds)
        XCTAssertEqual(master.tier, .master)
        XCTAssertEqual(master.score, 7.5, accuracy: 0.0001)
        XCTAssertNil(master.nextThreshold)
        XCTAssertEqual(RankingEngine.placement(metric: 9, thresholds: squat.thresholds).score, 8)
    }

    func testLoadRankUsesEpleyAndBodyweight() throws {
        let set = RankableSet(weightKg: 100, reps: 5, date: Date(), bodyweightKg: 80)
        let result = try RankingEngine.evaluate(set, standard: squat).get()
        XCTAssertEqual(try XCTUnwrap(result.estimatedOneRepMaxKg), 116.667, accuracy: 0.001)
        XCTAssertEqual(result.metric, 1.4583, accuracy: 0.001)
        XCTAssertEqual(result.placement.tier, .gold)
        XCTAssertFalse(set.isTestedMax)
        XCTAssertTrue(RankableSet(weightKg: 120, reps: 1, date: Date(), bodyweightKg: 80).isTestedMax)
    }

    func testMissingBodyweightIsReportedNotGuessed() {
        let set = RankableSet(weightKg: 100, reps: 5, date: Date(), bodyweightKg: nil)
        XCTAssertEqual(RankingEngine.evaluate(set, standard: squat), .failure(.missingBodyweight))
    }

    func testHighRepSetsAreNotRanked() {
        let set = RankableSet(weightKg: 60, reps: 20, date: Date(), bodyweightKg: 80)
        XCTAssertEqual(RankingEngine.evaluate(set, standard: squat), .failure(.tooManyReps))
    }

    func testZeroRepsAndZeroWeightAreRejected() {
        XCTAssertEqual(RankingEngine.evaluate(RankableSet(weightKg: 100, reps: 0, date: Date(), bodyweightKg: 80), standard: squat), .failure(.invalidSet))
        XCTAssertEqual(RankingEngine.evaluate(RankableSet(weightKg: 0, reps: 5, date: Date(), bodyweightKg: 80), standard: squat), .failure(.invalidSet))
    }

    func testRepRankingWithAndWithoutLoad() throws {
        let plain = try RankingEngine.evaluate(RankableSet(weightKg: 0, reps: 10, date: Date(), bodyweightKg: nil), standard: pullUp).get()
        XCTAssertEqual(plain.placement.tier, .gold)
        let weighted = try RankingEngine.evaluate(RankableSet(weightKg: 10, reps: 8, date: Date(), bodyweightKg: 80), standard: pullUp).get()
        XCTAssertEqual(weighted.metric, 12.75, accuracy: 0.001)
        XCTAssertEqual(weighted.placement.tier, .platinum)
        XCTAssertEqual(RankingEngine.evaluate(RankableSet(weightKg: 10, reps: 8, date: Date(), bodyweightKg: nil), standard: pullUp), .failure(.missingBodyweight))
    }

    func testEachExerciseUsesItsOwnThresholds() throws {
        let bench = RankingStandard(method: .relativeLoad, thresholds: [0.6, 0.85, 1.1, 1.35, 1.6, 1.85, 2.1], isCustom: false, note: "")
        let set = RankableSet(weightKg: 100, reps: 5, date: Date(), bodyweightKg: 80)
        XCTAssertEqual(try RankingEngine.evaluate(set, standard: bench).get().placement.tier, .platinum)
        XCTAssertEqual(try RankingEngine.evaluate(set, standard: squat).get().placement.tier, .gold)
    }

    func testScaleAppliesOnlyToDefaults() throws {
        let set = RankableSet(weightKg: 100, reps: 1, date: Date(), bodyweightKg: 100)
        XCTAssertEqual(try RankingEngine.evaluate(set, standard: squat, scale: 1).get().placement.tier, .silver)
        XCTAssertEqual(try RankingEngine.evaluate(set, standard: squat, scale: 0.7).get().placement.tier, .gold)
        var custom = squat
        custom.isCustom = true
        XCTAssertEqual(try RankingEngine.evaluate(set, standard: custom, scale: 0.7).get().placement.tier, .silver)
    }

    func testInvalidThresholdsAreRejected() {
        XCTAssertFalse(RankingStandard.isValid([1, 1, 2, 3, 4, 5, 6]))
        XCTAssertFalse(RankingStandard.isValid([2, 1, 3, 4, 5, 6, 7]))
        XCTAssertFalse(RankingStandard.isValid([0, 1, 2, 3, 4, 5, 6]))
        XCTAssertFalse(RankingStandard.isValid([0.5, 1, 1.5, 2]))
        XCTAssertTrue(RankingStandard.isValid([0.5, 1, 1.5, 2, 2.5, 3, 3.5]))
        let broken = RankingStandard(method: .relativeLoad, thresholds: [2, 1, 3, 4, 5, 6, 7], isCustom: true, note: "")
        XCTAssertEqual(RankingEngine.evaluate(RankableSet(weightKg: 100, reps: 3, date: Date(), bodyweightKg: 80), standard: broken), .failure(.invalidStandard))
    }

    func testLegacyThresholdsUpgradeKeepsTheirMeaning() throws {
        let upgraded = try XCTUnwrap(RankingStandard.upgradeLegacy([0.75, 1.25, 1.75, 2.25]))
        XCTAssertTrue(RankingStandard.isValid(upgraded))
        XCTAssertEqual(Array(upgraded.prefix(3)), [0.75, 1.25, 1.75])
        XCTAssertEqual(upgraded[5], 2.25, accuracy: 0.0001, "Old Elite stays Elite")
        XCTAssertGreaterThan(upgraded[6], upgraded[5])
        XCTAssertNil(RankingStandard.upgradeLegacy([2, 1, 3, 4]))
        XCTAssertNil(RankingStandard.upgradeLegacy([1, 2, 3]))
    }

    func testLadderIsStrictlyIncreasing() {
        let reps = RankingStandard.ladder(low: 3, high: 6, wholeNumbers: true)
        XCTAssertEqual(reps.count, 7)
        XCTAssertTrue(RankingStandard.isValid(reps))
        XCTAssertTrue(RankingStandard.isValid(RankingStandard.ladder(low: 0.5, high: 2)))
    }

    func testNextTierTargetGivesALoadableWeight() throws {
        let result = try RankingEngine.evaluate(RankableSet(weightKg: 100, reps: 5, date: Date(), bodyweightKg: 80), standard: squat).get()
        let target = try XCTUnwrap(NextTierTarget.make(for: result, increment: 2.5))
        XCTAssertEqual(target.tier, .platinum)
        XCTAssertEqual(try XCTUnwrap(target.oneRepMaxKg), 120, accuracy: 0.0001)
        // 120 / (1 + 5/30) = 102.86, rounded up to the next 2.5 kg.
        XCTAssertEqual(target.weightKg, 105)
        XCTAssertEqual(target.reps, 5)
        let top = try RankingEngine.evaluate(RankableSet(weightKg: 230, reps: 1, date: Date(), bodyweightKg: 80), standard: squat).get()
        XCTAssertNil(NextTierTarget.make(for: top, increment: 2.5))
    }

    func testBestPicksHighestMetricAndExplainsFailures() throws {
        let sets = [
            RankableSet(weightKg: 100, reps: 5, date: Date(), bodyweightKg: 80),
            RankableSet(weightKg: 110, reps: 3, date: Date(), bodyweightKg: 80),
            RankableSet(weightKg: 60, reps: 20, date: Date(), bodyweightKg: 80),
        ]
        let best = try RankingEngine.best(of: sets, standard: squat).get()
        // 110 × (1 + 3/30) = 121 beats 100 × (1 + 5/30) = 116.7; the 20-rep set is ignored.
        XCTAssertEqual(best.set.weightKg, 110)
        XCTAssertEqual(best.estimatedOneRepMaxKg ?? 0, 121, accuracy: 0.001)
        XCTAssertEqual(RankingEngine.best(of: [], standard: squat), .failure(.noSets))
        XCTAssertEqual(RankingEngine.best(of: [RankableSet(weightKg: 60, reps: 20, date: Date(), bodyweightKg: 80)], standard: squat), .failure(.tooManyReps))
        let unranked = RankingStandard(method: .unranked, thresholds: [], isCustom: false, note: "")
        XCTAssertEqual(RankingEngine.best(of: sets, standard: unranked), .failure(.unranked))
    }

    func testDistributionCountsTiersWithoutAnOverallRank() {
        let distribution = RankDistribution(tiers: [.gold, .silver, .gold, .unranked])
        XCTAssertEqual(distribution.tierCounts[.gold], 2)
        XCTAssertEqual(distribution.highest, .gold)
        XCTAssertEqual(distribution.rankedCount, 3)
        XCTAssertNil(RankDistribution(tiers: []).highest)
    }
}

final class UnitConversionTests: XCTestCase {
    func testPoundsRoundTrip() {
        let kg = WeightUnit.lb.toKilograms(225)
        XCTAssertEqual(kg, 102.0583, accuracy: 0.0001)
        XCTAssertEqual(WeightUnit.lb.fromKilograms(kg), 225, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.kg.toKilograms(80), 80)
    }

    func testFormattingInEachUnit() {
        XCTAssertEqual(Format.weight(100, unit: .kg), "100 kg")
        XCTAssertEqual(Format.weight(WeightUnit.lb.toKilograms(135), unit: .lb), "135 lb")
        XCTAssertEqual(Format.weight(21.25, unit: .kg, includeUnit: false), "21.25")
    }

    func testHeightConversion() {
        let parts = HeightConversion.feetAndInches(fromCentimetres: 180)
        XCTAssertEqual(parts.feet, 5)
        XCTAssertEqual(parts.inches, 11)
        XCTAssertEqual(HeightConversion.centimetres(feet: 6, inches: 0), 182.88, accuracy: 0.001)
    }

    func testClockAndDuration() {
        XCTAssertEqual(Format.clock(65), "1:05")
        XCTAssertEqual(Format.clock(3725), "1:02:05")
        XCTAssertEqual(Format.duration(3900), "1h 05m")
        XCTAssertEqual(Format.duration(45), "45s")
    }
}

final class InputValidatorTests: XCTestCase {
    func testParsesCommonNumberShapes() {
        XCTAssertEqual(InputValidator.parseNumber("82.5"), 82.5)
        XCTAssertEqual(InputValidator.parseNumber("82,5"), 82.5)
        XCTAssertEqual(InputValidator.parseNumber(" 100 "), 100)
        XCTAssertEqual(InputValidator.parseNumber("82."), 82)
        XCTAssertEqual(InputValidator.parseNumber(".5"), 0.5)
    }

    func testRejectsNonNumbers() {
        for text in ["", "abc", "1e5", "1.2.3", "--5", "5kg", ".", "∞", "NaN", "٣"] {
            XCTAssertNil(InputValidator.parseNumber(text), "\(text) should be rejected")
        }
    }

    func testWeightValidation() {
        XCTAssertEqual(InputValidator.weight("100", unit: .kg), .success(100))
        XCTAssertEqual(try InputValidator.weight("225", unit: .lb).get(), 102.0583, accuracy: 0.0001)
        XCTAssertEqual(InputValidator.weight("", unit: .kg), .failure(.empty))
        XCTAssertEqual(InputValidator.weight("-10", unit: .kg), .failure(.negative))
        XCTAssertEqual(InputValidator.weight("ten", unit: .kg), .failure(.notANumber))
        XCTAssertEqual(InputValidator.weight("0", unit: .kg, allowZero: false), .failure(.zero))
        if case .failure(.tooLarge) = InputValidator.weight("1001", unit: .kg) {} else { XCTFail("1001 kg should be too large") }
    }

    func testRepsValidation() {
        XCTAssertEqual(InputValidator.reps("8"), .success(8))
        XCTAssertEqual(InputValidator.reps("0"), .failure(.zero))
        XCTAssertEqual(InputValidator.reps("7.5"), .failure(.notWholeNumber))
        XCTAssertEqual(InputValidator.reps("-3"), .failure(.negative))
        XCTAssertEqual(InputValidator.reps(""), .failure(.empty))
        if case .failure(.tooLarge) = InputValidator.reps("501") {} else { XCTFail("501 reps should be too large") }
    }

    func testBodyweightRange() {
        if case .failure(.tooSmall) = InputValidator.bodyweight("10", unit: .kg) {} else { XCTFail("10 kg bodyweight is too small") }
        if case .failure(.tooLarge) = InputValidator.bodyweight("500", unit: .kg) {} else { XCTFail("500 kg bodyweight is too large") }
        XCTAssertEqual(InputValidator.bodyweight("80", unit: .kg), .success(80))
    }

    func testCompletedSetRules() {
        XCTAssertNil(InputValidator.completedSetError(weightKg: 100, reps: 5, requiresLoad: true))
        XCTAssertEqual(InputValidator.completedSetError(weightKg: nil, reps: 5, requiresLoad: true), .empty)
        XCTAssertEqual(InputValidator.completedSetError(weightKg: 0, reps: 5, requiresLoad: true), .zero)
        XCTAssertNil(InputValidator.completedSetError(weightKg: nil, reps: 12, requiresLoad: false))
        XCTAssertEqual(InputValidator.completedSetError(weightKg: 100, reps: nil, requiresLoad: true), .empty)
        XCTAssertEqual(InputValidator.completedSetError(weightKg: 100, reps: 0, requiresLoad: true), .zero)
        XCTAssertEqual(InputValidator.completedSetError(weightKg: -5, reps: 5, requiresLoad: false), .negative)
    }

    func testTimedSetsAllowLongHolds() {
        XCTAssertNil(InputValidator.completedSetError(weightKg: nil, reps: 90, requiresLoad: false, timed: true))
        XCTAssertNil(InputValidator.completedSetError(weightKg: nil, reps: 900, requiresLoad: false, timed: true))
        XCTAssertNotNil(InputValidator.completedSetError(weightKg: nil, reps: 900, requiresLoad: false))
        XCTAssertNotNil(InputValidator.completedSetError(weightKg: nil, reps: 4000, requiresLoad: false, timed: true))
        XCTAssertEqual(InputValidator.count("45", timed: true), .success(45))
        XCTAssertEqual(Format.hold(45), "45 s")
        XCTAssertEqual(Format.hold(95), "1:35")
    }
}
