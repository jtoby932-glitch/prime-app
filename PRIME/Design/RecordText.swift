import Foundation
import SwiftData

extension RecordKind {
    func valueText(value: Double, weightKg: Double, reps: Int, unit: WeightUnit) -> String {
        switch self {
        case .heaviestWeight: return Format.weight(value, unit: unit) + (reps > 0 ? " × \(reps)" : "")
        case .bestOneRepMax: return "\(Format.estimate(value, unit: unit)) e1RM"
        case .bestSetVolume: return "\(Format.weight(weightKg, unit: unit)) × \(reps)"
        case .bestSessionVolume: return "\(Format.volume(value, unit: unit)) total"
        case .mostRepsAtWeight:
            return weightKg > 0 ? "\(Int(value)) reps at \(Format.weight(weightKg, unit: unit))" : "\(Int(value)) reps"
        }
    }

    func improvementText(value: Double, previous: Double?, unit: WeightUnit) -> String? {
        guard let previous, previous > 0 else { return nil }
        switch self {
        case .mostRepsAtWeight:
            let gain = Int(value - previous)
            return gain > 0 ? "+\(gain) rep\(gain == 1 ? "" : "s")" : nil
        default:
            let gain = value - previous
            guard gain > 0 else { return nil }
            return "+" + Format.weight(gain, unit: unit)
        }
    }
}

extension PersonalRecord {
    func valueText(unit: WeightUnit) -> String { kind.valueText(value: value, weightKg: weightKg, reps: reps, unit: unit) }
    func improvementText(unit: WeightUnit) -> String? { kind.improvementText(value: value, previous: previousValue, unit: unit) }
}

extension PRAchievement {
    func valueText(unit: WeightUnit) -> String { kind.valueText(value: value, weightKg: weightKg, reps: reps, unit: unit) }
    func improvementText(unit: WeightUnit) -> String? { kind.improvementText(value: value, previous: previous, unit: unit) }
}

extension Date {
    /// "Today", "Yesterday", "Mon 3 Nov" or "3 Nov 2025".
    var relativeDayText: String {
        let calendar = Calendar.prime
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }
}

@MainActor
extension AppState {
    /// Starts a workout, or reopens the one already in progress.
    func startWorkout(plan: WorkoutPlan?, context: ModelContext, store: TrainingStore) {
        if activeSession != nil {
            isWorkoutPresented = true
            show(Toast(title: "Workout already running", message: "Finish or discard it before starting another.", style: .warning))
            return
        }
        let session = WorkoutService.start(plan: plan, context: context, history: store.history)
        Haptics.thud()
        begin(session)
    }
}
