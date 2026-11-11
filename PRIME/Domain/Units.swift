import Foundation

enum WeightUnit: String, CaseIterable, Codable, Identifiable {
    case kg, lb

    static let kilogramsPerPound = 0.45359237

    var id: String { rawValue }
    var symbol: String { rawValue }
    var displayName: String { self == .kg ? "Kilograms (kg)" : "Pounds (lb)" }

    func fromKilograms(_ kilograms: Double) -> Double {
        self == .kg ? kilograms : kilograms / Self.kilogramsPerPound
    }

    func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value * Self.kilogramsPerPound
    }

    /// Typical smallest jump on a gym floor.
    var increment: Double { self == .kg ? 2.5 : 5 }
}

enum MeasurementSystem: String, CaseIterable, Codable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var displayName: String { self == .metric ? "Metric (cm)" : "Imperial (ft, in)" }
}

enum HeightConversion {
    static let centimetresPerInch = 2.54

    static func feetAndInches(fromCentimetres cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / centimetresPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    static func centimetres(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * centimetresPerInch
    }
}

enum Format {
    /// "102.5", "225", "21.25" — up to two decimals, no trailing zeros.
    static func number(_ value: Double, maxFractionDigits: Int = 2) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).grouping(.never))
    }

    static func weight(_ kilograms: Double, unit: WeightUnit, includeUnit: Bool = true) -> String {
        let value = number(unit.fromKilograms(kilograms))
        return includeUnit ? "\(value) \(unit.symbol)" : value
    }

    /// Estimated values (e1RM and the like) are rounded to one decimal so they don't look more precise than they are.
    static func estimate(_ kilograms: Double, unit: WeightUnit, decimals: Int = 1) -> String {
        "\(number(unit.fromKilograms(kilograms), maxFractionDigits: decimals)) \(unit.symbol)"
    }

    /// Volume in the user's unit, compacted above 100k ("12,450 kg", "184k kg").
    static func volume(_ kilograms: Double, unit: WeightUnit, includeUnit: Bool = true) -> String {
        let value = unit.fromKilograms(kilograms)
        let text: String
        if value >= 100_000 {
            text = (value / 1000).formatted(.number.precision(.fractionLength(0))) + "k"
        } else {
            text = value.formatted(.number.precision(.fractionLength(0)))
        }
        return includeUnit ? "\(text) \(unit.symbol)" : text
    }

    static func set(weightKg: Double?, reps: Int?, unit: WeightUnit) -> String {
        switch (weightKg, reps) {
        case let (w?, r?) where w > 0: return "\(weight(w, unit: unit)) × \(r)"
        case let (_, r?): return "\(r) reps"
        case let (w?, nil): return weight(w, unit: unit)
        default: return "–"
        }
    }

    /// "1h 04m", "52m", "45s"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// "1:04:09" or "4:09" for live clocks.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func ratio(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + "× BW"
    }

    static func percent(_ fraction: Double) -> String {
        Int((fraction * 100).rounded()).formatted() + "%"
    }

    static func height(cm: Double, system: MeasurementSystem) -> String {
        switch system {
        case .metric: return "\(Int(cm.rounded())) cm"
        case .imperial:
            let parts = HeightConversion.feetAndInches(fromCentimetres: cm)
            return "\(parts.feet)′ \(parts.inches)″"
        }
    }
}
