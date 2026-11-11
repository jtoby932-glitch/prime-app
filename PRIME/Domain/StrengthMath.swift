import Foundation

enum StrengthMath {
    /// Above this the Epley estimate drifts badly, so PRIME doesn't rank on it.
    static let reliableRepLimit = 12

    /// Epley: 1RM = weight × (1 + reps / 30).
    /// A single rep is already a one-rep max, so it returns the weight itself.
    /// Returns nil for zero/negative reps, zero/negative weight or non-finite input.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight.isFinite, weight > 0, reps > 0 else { return nil }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Estimated 1RM ÷ bodyweight. Nil when bodyweight is missing or invalid.
    static func relativeStrength(oneRepMax: Double, bodyweight: Double?) -> Double? {
        guard let bodyweight, bodyweight.isFinite, bodyweight > 0, oneRepMax.isFinite, oneRepMax > 0 else { return nil }
        return oneRepMax / bodyweight
    }

    /// Converts a weighted bodyweight set (e.g. pull-ups with +10 kg) into the number of
    /// unweighted reps that would need the same estimated 1RM, using Epley both ways.
    static func bodyweightEquivalentReps(bodyweight: Double?, addedWeight: Double, reps: Int) -> Double? {
        guard reps > 0 else { return nil }
        if addedWeight <= 0 { return Double(reps) }
        guard let bodyweight, bodyweight > 0, reps <= reliableRepLimit else { return nil }
        let total = bodyweight + addedWeight
        let oneRepMax = total * (1 + Double(reps) / 30)
        return 30 * (oneRepMax / bodyweight - 1)
    }

    /// Weight × reps. Bodyweight sets carry no external load, so they add 0.
    static func setVolume(weight: Double?, reps: Int?) -> Double {
        guard let weight, let reps, weight > 0, reps > 0, weight.isFinite else { return 0 }
        return weight * Double(reps)
    }
}
