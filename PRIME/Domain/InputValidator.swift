import Foundation

enum ValidationError: Error, Equatable, LocalizedError {
    case empty
    case notANumber
    case negative
    case zero
    case notWholeNumber
    case tooLarge(limit: String)
    case tooSmall(limit: String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Enter a value"
        case .notANumber: return "Numbers only"
        case .negative: return "Can't be negative"
        case .zero: return "Must be more than zero"
        case .notWholeNumber: return "Whole numbers only"
        case .tooLarge(let limit): return "Max \(limit)"
        case .tooSmall(let limit): return "Min \(limit)"
        }
    }
}

/// Every number typed into PRIME passes through here. Nothing is silently accepted:
/// a value is either valid and converted to kilograms, or rejected with a reason.
enum InputValidator {
    static let maxWeightKg = 1000.0
    static let maxReps = 500
    static let bodyweightRangeKg = 20.0...400.0
    static let restRangeSeconds = 0...900
    static let setRange = 1...20

    /// Parses "82.5", "82,5", "82." and ".5". Rejects letters, signs, exponents and multiple separators.
    static func parseNumber(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return nil }
        var separators = 0
        var digits = 0
        for character in text {
            if character == "." {
                separators += 1
            } else if character.isASCII, character.isNumber {
                digits += 1
            } else {
                return nil
            }
        }
        guard separators <= 1, digits > 0 else { return nil }
        let normalised = text.hasSuffix(".") ? String(text.dropLast()) : text
        let value = Double(normalised.hasPrefix(".") ? "0" + normalised : normalised)
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Returns kilograms.
    static func weight(_ raw: String, unit: WeightUnit, allowZero: Bool = true) -> Result<Double, ValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.hasPrefix("-") { return .failure(.negative) }
        guard let value = parseNumber(trimmed) else { return .failure(.notANumber) }
        if value == 0 && !allowZero { return .failure(.zero) }
        let kilograms = unit.toKilograms(value)
        if kilograms > maxWeightKg {
            return .failure(.tooLarge(limit: Format.weight(maxWeightKg, unit: unit)))
        }
        return .success(kilograms)
    }

    static func reps(_ raw: String) -> Result<Int, ValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.hasPrefix("-") { return .failure(.negative) }
        guard let value = parseNumber(trimmed) else { return .failure(.notANumber) }
        guard value == value.rounded(), !trimmed.contains(".") && !trimmed.contains(",") else {
            return .failure(.notWholeNumber)
        }
        let reps = Int(value)
        if reps == 0 { return .failure(.zero) }
        if reps > maxReps { return .failure(.tooLarge(limit: "\(maxReps)")) }
        return .success(reps)
    }

    static func bodyweight(_ raw: String, unit: WeightUnit) -> Result<Double, ValidationError> {
        switch weight(raw, unit: unit, allowZero: false) {
        case .failure(let error): return .failure(error)
        case .success(let kilograms):
            if kilograms < bodyweightRangeKg.lowerBound {
                return .failure(.tooSmall(limit: Format.weight(bodyweightRangeKg.lowerBound, unit: unit)))
            }
            if kilograms > bodyweightRangeKg.upperBound {
                return .failure(.tooLarge(limit: Format.weight(bodyweightRangeKg.upperBound, unit: unit)))
            }
            return .success(kilograms)
        }
    }

    /// A set can only be completed with valid reps, and a load when the equipment needs one.
    static func completedSetError(weightKg: Double?, reps: Int?, requiresLoad: Bool) -> ValidationError? {
        guard let reps else { return .empty }
        if reps <= 0 { return .zero }
        if reps > maxReps { return .tooLarge(limit: "\(maxReps)") }
        if let weightKg {
            if !weightKg.isFinite { return .notANumber }
            if weightKg < 0 { return .negative }
            if weightKg > maxWeightKg { return .tooLarge(limit: "\(Int(maxWeightKg)) kg") }
            if requiresLoad && weightKg == 0 { return .zero }
        } else if requiresLoad {
            return .empty
        }
        return nil
    }
}
