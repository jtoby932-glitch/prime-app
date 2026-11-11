import Foundation

// MARK: - Muscle groups

enum MuscleGroup: String, CaseIterable, Codable, Identifiable, Hashable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quadriceps, hamstrings, glutes, calves, abdominals, lowerBack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quadriceps: return "Quadriceps"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .abdominals: return "Abdominals"
        case .lowerBack: return "Lower back"
        }
    }

    var shortName: String {
        switch self {
        case .quadriceps: return "Quads"
        case .abdominals: return "Abs"
        case .lowerBack: return "Low back"
        default: return displayName
        }
    }

    /// Which side of the body the muscle is best seen from.
    var anatomySide: AnatomySide {
        switch self {
        case .chest, .shoulders, .biceps, .forearms, .quadriceps, .abdominals: return .front
        case .back, .triceps, .hamstrings, .glutes, .calves, .lowerBack: return .back
        }
    }

    var region: BodyRegion {
        switch self {
        case .chest, .shoulders, .triceps: return .push
        case .back, .biceps, .forearms, .lowerBack: return .pull
        case .quadriceps, .hamstrings, .glutes, .calves: return .legs
        case .abdominals: return .core
        }
    }

    static func from(_ raws: [String]) -> [MuscleGroup] { raws.compactMap(MuscleGroup.init(rawValue:)) }
}

enum AnatomySide: String, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
    var displayName: String { self == .front ? "Front" : "Back" }
}

enum BodyRegion: String, CaseIterable {
    case push, pull, legs, core
    var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }
}

// MARK: - Equipment

enum Equipment: String, CaseIterable, Codable, Identifiable, Hashable {
    case barbell, dumbbell, cable, machine, bodyweight, band

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbells"
        case .cable: return "Cable"
        case .machine: return "Machine"
        case .bodyweight: return "Bodyweight"
        case .band: return "Resistance band"
        }
    }

    var symbol: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .cable: return "point.3.connected.trianglepath.dotted"
        case .machine: return "gearshape.2.fill"
        case .bodyweight: return "figure.core.training"
        case .band: return "infinity"
        }
    }

    /// Free weights and machines are never compared with each other.
    var isFreeWeight: Bool {
        switch self {
        case .barbell, .dumbbell, .bodyweight, .band: return true
        case .cable, .machine: return false
        }
    }

    /// Whether a set normally needs an external load to be meaningful.
    var requiresLoad: Bool {
        switch self {
        case .bodyweight, .band: return false
        default: return true
        }
    }
}

enum Mechanic: String, CaseIterable, Codable, Identifiable {
    case compound, isolation
    var id: String { rawValue }
    var displayName: String { self == .compound ? "Compound" : "Isolation" }
}

enum Difficulty: String, CaseIterable, Codable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var level: Int {
        switch self {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        }
    }
}

// MARK: - Profile options

enum ExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case new, beginner, intermediate, advanced
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .new: return "Just starting"
        case .beginner: return "Under a year"
        case .intermediate: return "1–3 years"
        case .advanced: return "3+ years"
        }
    }
}

enum TrainingInterest: String, CaseIterable, Codable, Identifiable {
    case strength, muscle, generalFitness, powerlifting, athletic, endurance
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .strength: return "Get stronger"
        case .muscle: return "Build muscle"
        case .generalFitness: return "General fitness"
        case .powerlifting: return "Powerlifting"
        case .athletic: return "Athletic performance"
        case .endurance: return "Muscular endurance"
        }
    }
    var symbol: String {
        switch self {
        case .strength: return "bolt.fill"
        case .muscle: return "figure.strengthtraining.functional"
        case .generalFitness: return "heart.fill"
        case .powerlifting: return "figure.strengthtraining.traditional"
        case .athletic: return "figure.run"
        case .endurance: return "timer"
        }
    }
}

enum SessionStatus: String, Codable {
    case active, completed
}

enum RecordKind: String, CaseIterable, Codable, Identifiable {
    case heaviestWeight, bestOneRepMax, bestSetVolume, bestSessionVolume, mostRepsAtWeight
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .heaviestWeight: return "Heaviest weight"
        case .bestOneRepMax: return "Best est. 1RM"
        case .bestSetVolume: return "Best set volume"
        case .bestSessionVolume: return "Best session volume"
        case .mostRepsAtWeight: return "Most reps at weight"
        }
    }
    var symbol: String {
        switch self {
        case .heaviestWeight: return "scalemass.fill"
        case .bestOneRepMax: return "bolt.fill"
        case .bestSetVolume: return "square.stack.3d.up.fill"
        case .bestSessionVolume: return "chart.bar.fill"
        case .mostRepsAtWeight: return "repeat"
        }
    }
}

// MARK: - Weekdays (0 = Monday … 6 = Sunday)

enum Weekday {
    static let all = Array(0..<7)
    static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let longNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let initials = ["M", "T", "W", "T", "F", "S", "S"]

    static func index(of date: Date, calendar: Calendar = .prime) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// Apple's weekday numbering (1 = Sunday … 7 = Saturday).
    static func appleWeekday(for index: Int) -> Int {
        index == 6 ? 1 : index + 2
    }
}

extension Calendar {
    /// Gregorian, weeks start on Monday.
    static var prime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}
