import Foundation

/// The best marks for one exercise, built from history.
struct RecordSnapshot: Equatable {
    var heaviestWeightKg: Double?
    var bestOneRepMaxKg: Double?
    var bestSetVolume: Double?
    var bestSessionVolume: Double?
    /// Weight (in grams, to avoid floating point keys) → most reps done at it.
    var mostRepsByWeight: [Int: Int] = [:]
    var hasHistory: Bool = false

    static let empty = RecordSnapshot()

    static func from(_ samples: [SetSample]) -> RecordSnapshot {
        var snapshot = RecordSnapshot()
        guard !samples.isEmpty else { return snapshot }
        snapshot.hasHistory = true
        for sample in samples { snapshot.absorb(weightKg: sample.weightKg, reps: sample.reps) }
        for (_, sets) in Dictionary(grouping: samples, by: \.sessionID) {
            let volume = Analytics.totalVolume(sets)
            if volume > 0 { snapshot.bestSessionVolume = max(snapshot.bestSessionVolume ?? 0, volume) }
        }
        return snapshot
    }

    /// Adds one session's sets for this exercise.
    mutating func absorbSession(_ sets: [(weightKg: Double, reps: Int)]) {
        guard !sets.isEmpty else { return }
        hasHistory = true
        for set in sets { absorb(weightKg: set.weightKg, reps: set.reps) }
        let volume = sets.reduce(0) { $0 + StrengthMath.setVolume(weight: $1.weightKg, reps: $1.reps) }
        if volume > 0 { bestSessionVolume = max(bestSessionVolume ?? 0, volume) }
    }

    mutating func absorb(weightKg: Double, reps: Int) {
        guard reps > 0, weightKg >= 0, weightKg.isFinite else { return }
        if weightKg > 0 { heaviestWeightKg = max(heaviestWeightKg ?? 0, weightKg) }
        if let estimate = StrengthMath.estimatedOneRepMax(weight: weightKg, reps: reps) {
            bestOneRepMaxKg = max(bestOneRepMaxKg ?? 0, estimate)
        }
        let volume = StrengthMath.setVolume(weight: weightKg, reps: reps)
        if volume > 0 { bestSetVolume = max(bestSetVolume ?? 0, volume) }
        let key = PRDetector.weightKey(weightKg)
        mostRepsByWeight[key] = max(mostRepsByWeight[key] ?? 0, reps)
    }
}

struct PRAchievement: Equatable, Hashable, Identifiable {
    let kind: RecordKind
    let value: Double
    let weightKg: Double
    let reps: Int
    let previous: Double?
    var id: String { "\(kind.rawValue)-\(weightKg)-\(reps)-\(value)" }
}

enum PRDetector {
    static func weightKey(_ kilograms: Double) -> Int { Int((kilograms * 1000).rounded()) }

    /// Records a single set beats. Empty when the exercise has no earlier history:
    /// a first attempt sets the baseline rather than "beating" anything.
    static func recordsBeaten(weightKg: Double, reps: Int, against snapshot: RecordSnapshot) -> [RecordKind] {
        guard snapshot.hasHistory, reps > 0, weightKg >= 0 else { return [] }
        var kinds: [RecordKind] = []
        if weightKg > 0, let best = snapshot.heaviestWeightKg, weightKg > best + 1e-9 { kinds.append(.heaviestWeight) }
        if let estimate = StrengthMath.estimatedOneRepMax(weight: weightKg, reps: reps),
           let best = snapshot.bestOneRepMaxKg, estimate > best + 1e-9 { kinds.append(.bestOneRepMax) }
        let volume = StrengthMath.setVolume(weight: weightKg, reps: reps)
        if volume > 0, let best = snapshot.bestSetVolume, volume > best + 1e-9 { kinds.append(.bestSetVolume) }
        if let best = snapshot.mostRepsByWeight[weightKey(weightKg)], reps > best { kinds.append(.mostRepsAtWeight) }
        return kinds
    }

    /// New records from one exercise's sets in a finished session, compared with history before it.
    static func sessionRecords(sets: [(weightKg: Double, reps: Int)], against history: RecordSnapshot) -> [PRAchievement] {
        let valid = sets.filter { $0.reps > 0 && $0.weightKg >= 0 && $0.weightKg.isFinite }
        guard history.hasHistory, !valid.isEmpty else { return [] }
        var achievements: [PRAchievement] = []

        if let top = valid.filter({ $0.weightKg > 0 }).max(by: { $0.weightKg < $1.weightKg }),
           let previous = history.heaviestWeightKg, top.weightKg > previous + 1e-9 {
            achievements.append(PRAchievement(kind: .heaviestWeight, value: top.weightKg, weightKg: top.weightKg, reps: top.reps, previous: previous))
        }

        let estimates = valid.compactMap { set in
            StrengthMath.estimatedOneRepMax(weight: set.weightKg, reps: set.reps).map { (set, $0) }
        }
        if let top = estimates.max(by: { $0.1 < $1.1 }), let previous = history.bestOneRepMaxKg, top.1 > previous + 1e-9 {
            achievements.append(PRAchievement(kind: .bestOneRepMax, value: top.1, weightKg: top.0.weightKg, reps: top.0.reps, previous: previous))
        }

        if let top = valid.max(by: { $0.weightKg * Double($0.reps) < $1.weightKg * Double($1.reps) }) {
            let volume = StrengthMath.setVolume(weight: top.weightKg, reps: top.reps)
            if volume > 0, let previous = history.bestSetVolume, volume > previous + 1e-9 {
                achievements.append(PRAchievement(kind: .bestSetVolume, value: volume, weightKg: top.weightKg, reps: top.reps, previous: previous))
            }
        }

        let sessionVolume = valid.reduce(0) { $0 + StrengthMath.setVolume(weight: $1.weightKg, reps: $1.reps) }
        if sessionVolume > 0, let previous = history.bestSessionVolume, sessionVolume > previous + 1e-9 {
            achievements.append(PRAchievement(kind: .bestSessionVolume, value: sessionVolume, weightKg: 0, reps: 0, previous: previous))
        }

        // Rep records: the biggest improvement at any weight done before.
        var bestRepGain: (weightKg: Double, reps: Int, previous: Int)?
        for (key, sets) in Dictionary(grouping: valid, by: { weightKey($0.weightKg) }) {
            guard let previous = history.mostRepsByWeight[key], let top = sets.map(\.reps).max(), top > previous else { continue }
            if bestRepGain == nil || top - previous > bestRepGain!.reps - bestRepGain!.previous {
                bestRepGain = (sets[0].weightKg, top, previous)
            }
        }
        if let gain = bestRepGain {
            achievements.append(PRAchievement(kind: .mostRepsAtWeight, value: Double(gain.reps), weightKg: gain.weightKg, reps: gain.reps, previous: Double(gain.previous)))
        }
        return achievements
    }
}

/// The best reps done at each weight, for an exercise's "rep records" table.
enum RepRecords {
    static func table(_ samples: [SetSample]) -> [(weightKg: Double, reps: Int, date: Date)] {
        var best: [Int: (weightKg: Double, reps: Int, date: Date)] = [:]
        for sample in samples where sample.reps > 0 {
            let key = PRDetector.weightKey(sample.weightKg)
            if let current = best[key], current.reps >= sample.reps { continue }
            best[key] = (sample.weightKg, sample.reps, sample.date)
        }
        return best.values.sorted { $0.weightKg > $1.weightKg }
    }
}
