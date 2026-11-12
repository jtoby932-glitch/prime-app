import Foundation

// MARK: - Muscle groups

/// Raw values are stored in the database, so existing ones never change.
enum MuscleGroup: String, CaseIterable, Codable, Identifiable, Hashable {
    case chest, back, traps, shoulders, biceps, triceps, forearms
    case abdominals, lowerBack
    case quadriceps, hamstrings, glutes, adductors, abductors, calves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .traps: return "Traps"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .abdominals: return "Core"
        case .lowerBack: return "Lower back"
        case .quadriceps: return "Quadriceps"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        case .calves: return "Calves"
        }
    }

    var shortName: String {
        switch self {
        case .quadriceps: return "Quads"
        case .lowerBack: return "Low back"
        case .hamstrings: return "Hams"
        default: return displayName
        }
    }

    var region: BodyRegion {
        switch self {
        case .chest, .shoulders, .triceps: return .push
        case .back, .traps, .biceps, .forearms: return .pull
        case .quadriceps, .hamstrings, .glutes, .adductors, .abductors, .calves: return .legs
        case .abdominals, .lowerBack: return .core
        }
    }

    /// Large groups used when comparing how evenly training is spread.
    var isMajor: Bool {
        switch self {
        case .chest, .back, .shoulders, .quadriceps, .hamstrings, .glutes: return true
        default: return false
        }
    }

    static func from(_ raws: [String]) -> [MuscleGroup] { raws.compactMap(MuscleGroup.init(rawValue:)) }
}

/// Plain-language reference for the muscle explorer.
struct MuscleInfo {
    let anatomicalName: String
    let location: String
    let function: String
    let movements: [String]

    static func of(_ muscle: MuscleGroup) -> MuscleInfo {
        switch muscle {
        case .chest:
            return MuscleInfo(anatomicalName: "Pectoralis major and minor",
                              location: "Front of the upper torso, from the breastbone and collarbone to the upper arm.",
                              function: "Brings the upper arm across and in front of the body, and helps push forwards.",
                              movements: ["Horizontal pressing", "Flyes", "Dips"])
        case .back:
            return MuscleInfo(anatomicalName: "Latissimus dorsi, rhomboids, teres major and infraspinatus",
                              location: "The width of the back, from the lower spine and pelvis up to the shoulder blades and upper arm.",
                              function: "Pulls the arms down and back, and draws the shoulder blades together.",
                              movements: ["Vertical pulling", "Horizontal rowing", "Pullovers"])
        case .traps:
            return MuscleInfo(anatomicalName: "Trapezius",
                              location: "Kite-shaped muscle from the base of the skull and neck down the middle of the upper back.",
                              function: "Lifts, squeezes together and lowers the shoulder blades, and supports the neck.",
                              movements: ["Shrugging", "Rowing", "Carrying"])
        case .shoulders:
            return MuscleInfo(anatomicalName: "Deltoids (front, side and rear heads)",
                              location: "The rounded cap over the top of each shoulder joint.",
                              function: "Lifts the arm forwards, out to the side and backwards.",
                              movements: ["Overhead pressing", "Lateral raises", "Rear-delt flyes"])
        case .biceps:
            return MuscleInfo(anatomicalName: "Biceps brachii and brachialis",
                              location: "Front of the upper arm, between the shoulder and the elbow.",
                              function: "Bends the elbow and turns the palm to face up.",
                              movements: ["Curls", "Chin-ups", "Rows"])
        case .triceps:
            return MuscleInfo(anatomicalName: "Triceps brachii (long, lateral and medial heads)",
                              location: "Back of the upper arm, between the shoulder and the elbow.",
                              function: "Straightens the elbow; the long head also helps bring the arm down and back.",
                              movements: ["Pressing", "Pushdowns", "Overhead extensions"])
        case .forearms:
            return MuscleInfo(anatomicalName: "Wrist flexors, wrist extensors and brachioradialis",
                              location: "Between the elbow and the wrist.",
                              function: "Bends and straightens the wrist, grips, and helps bend the elbow.",
                              movements: ["Gripping", "Wrist curls", "Hammer curls"])
        case .abdominals:
            return MuscleInfo(anatomicalName: "Rectus abdominis, obliques and transversus abdominis",
                              location: "The front and sides of the trunk, between the ribs and the pelvis.",
                              function: "Bends and rotates the trunk, and holds it steady against movement.",
                              movements: ["Crunching", "Bracing", "Anti-rotation"])
        case .lowerBack:
            return MuscleInfo(anatomicalName: "Erector spinae",
                              location: "Two columns of muscle either side of the lower spine.",
                              function: "Straightens the spine and holds it in position when you bend at the hips.",
                              movements: ["Hip hinging", "Back extensions", "Deadlifts"])
        case .quadriceps:
            return MuscleInfo(anatomicalName: "Quadriceps femoris (four heads)",
                              location: "Front of the thigh, from the hip to just below the knee.",
                              function: "Straightens the knee; one head also helps lift the thigh.",
                              movements: ["Squatting", "Leg pressing", "Lunging"])
        case .hamstrings:
            return MuscleInfo(anatomicalName: "Biceps femoris, semitendinosus and semimembranosus",
                              location: "Back of the thigh, from the sitting bone to just below the knee.",
                              function: "Bends the knee and extends the hip.",
                              movements: ["Hip hinging", "Leg curls", "Nordic curls"])
        case .glutes:
            return MuscleInfo(anatomicalName: "Gluteus maximus",
                              location: "The buttocks, from the pelvis to the top of the thigh bone.",
                              function: "Extends the hip, driving it forwards from a bent position.",
                              movements: ["Hip thrusting", "Squatting", "Hip hinging"])
        case .adductors:
            return MuscleInfo(anatomicalName: "Adductor magnus, longus and brevis, and gracilis",
                              location: "The inner thigh, from the pelvis to the inside of the thigh bone.",
                              function: "Brings the leg in towards the midline and steadies the hip.",
                              movements: ["Adduction", "Wide-stance squats", "Lunges"])
        case .abductors:
            return MuscleInfo(anatomicalName: "Gluteus medius and minimus, and tensor fasciae latae",
                              location: "The upper outer hip, above and to the side of the gluteus maximus.",
                              function: "Moves the leg out to the side and keeps the pelvis level when standing on one leg.",
                              movements: ["Abduction", "Single-leg work", "Lateral walks"])
        case .calves:
            return MuscleInfo(anatomicalName: "Gastrocnemius, soleus and tibialis anterior",
                              location: "The lower leg, between the knee and the ankle.",
                              function: "Points the foot down (calf) and pulls it up (shin).",
                              movements: ["Calf raises", "Jumping", "Walking"])
        }
    }
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

/// How a set is measured. Timed holds store seconds in the reps field.
enum TrackingType: String, Codable {
    case weightReps, reps, time

    var countLabel: String { self == .time ? "SEC" : "REPS" }
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
    case heaviestWeight, bestOneRepMax, bestSetVolume, bestSessionVolume, mostRepsAtWeight, longestHold
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .heaviestWeight: return "Heaviest weight"
        case .bestOneRepMax: return "Best est. 1RM"
        case .bestSetVolume: return "Best set volume"
        case .bestSessionVolume: return "Best session volume"
        case .mostRepsAtWeight: return "Most reps at weight"
        case .longestHold: return "Longest hold"
        }
    }
    var symbol: String {
        switch self {
        case .heaviestWeight: return "scalemass.fill"
        case .bestOneRepMax: return "bolt.fill"
        case .bestSetVolume: return "square.stack.3d.up.fill"
        case .bestSessionVolume: return "chart.bar.fill"
        case .mostRepsAtWeight: return "repeat"
        case .longestHold: return "stopwatch.fill"
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
