import Foundation

/// A reusable workout that presets are built from. Applying a preset copies these into the
/// user's own routines, so editing a routine never changes the template.
struct WorkoutTemplate: Identifiable, Equatable {
    struct Item: Equatable {
        let slug: String
        let sets: Int
        let reps: Int
    }

    let id: String
    let name: String
    let items: [Item]

    static let library: [String: WorkoutTemplate] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static func t(_ id: String, _ name: String, _ items: [(String, Int, Int)]) -> WorkoutTemplate {
        WorkoutTemplate(id: id, name: name, items: items.map { Item(slug: $0.0, sets: $0.1, reps: $0.2) })
    }

    static let all: [WorkoutTemplate] = [
        t("push", "Push", [("barbell-bench-press", 4, 6), ("incline-dumbbell-press", 3, 10), ("dumbbell-shoulder-press", 3, 10),
                           ("dumbbell-lateral-raise", 3, 15), ("cable-triceps-pushdown", 3, 12), ("overhead-cable-triceps-extension", 3, 12)]),
        t("pull", "Pull", [("pull-up", 4, 8), ("barbell-bent-over-row", 3, 8), ("seated-cable-row", 3, 10),
                           ("face-pull", 3, 15), ("barbell-curl", 3, 10), ("hammer-curl", 3, 12)]),
        t("legs", "Legs", [("barbell-back-squat", 4, 6), ("romanian-deadlift", 3, 8), ("leg-press", 3, 10),
                           ("leg-extension", 3, 12), ("seated-leg-curl", 3, 12), ("standing-calf-raise", 4, 12)]),
        t("upper", "Upper Body", [("barbell-bench-press", 4, 6), ("barbell-bent-over-row", 4, 8), ("overhead-press", 3, 8),
                                  ("lat-pulldown", 3, 10), ("dumbbell-bicep-curl", 3, 12), ("cable-triceps-pushdown", 3, 12)]),
        t("lower", "Lower Body", [("barbell-back-squat", 4, 6), ("romanian-deadlift", 3, 8), ("bulgarian-split-squat", 3, 10),
                                  ("lying-leg-curl", 3, 12), ("standing-calf-raise", 4, 12), ("hanging-leg-raise", 3, 10)]),
        t("chestBack", "Chest & Back", [("barbell-bench-press", 4, 8), ("pull-up", 4, 8), ("incline-dumbbell-press", 3, 10),
                                         ("barbell-bent-over-row", 3, 10), ("cable-fly", 3, 12), ("straight-arm-pulldown", 3, 12)]),
        t("shouldersArms", "Shoulders & Arms", [("overhead-press", 4, 8), ("dumbbell-lateral-raise", 4, 15), ("reverse-pec-deck", 3, 15),
                                                 ("barbell-curl", 3, 10), ("skull-crusher", 3, 10), ("hammer-curl", 3, 12),
                                                 ("overhead-cable-triceps-extension", 3, 12)]),
        t("chest", "Chest", [("barbell-bench-press", 4, 6), ("incline-dumbbell-press", 3, 10), ("decline-bench-press", 3, 10),
                             ("cable-fly", 3, 12), ("chest-dip", 3, 10)]),
        t("back", "Back", [("conventional-deadlift", 3, 5), ("pull-up", 4, 8), ("t-bar-row", 3, 10),
                           ("lat-pulldown", 3, 10), ("seated-cable-row", 3, 12)]),
        t("shoulders", "Shoulders", [("overhead-press", 4, 6), ("dumbbell-lateral-raise", 4, 15), ("cable-lateral-raise", 3, 15),
                                     ("reverse-pec-deck", 3, 15), ("barbell-shrug", 3, 12)]),
        t("arms", "Arms", [("barbell-curl", 4, 10), ("close-grip-bench-press", 4, 8), ("incline-dumbbell-curl", 3, 12),
                           ("overhead-cable-triceps-extension", 3, 12), ("hammer-curl", 3, 12), ("cable-triceps-pushdown", 3, 12)]),
        t("fullA", "Full Body A", [("barbell-back-squat", 3, 5), ("barbell-bench-press", 3, 5), ("barbell-bent-over-row", 3, 8),
                                   ("dumbbell-shoulder-press", 3, 10), ("plank", 3, 45)]),
        t("fullB", "Full Body B", [("conventional-deadlift", 3, 5), ("overhead-press", 3, 6), ("lat-pulldown", 3, 10),
                                   ("dumbbell-walking-lunge", 3, 10), ("cable-crunch", 3, 12)]),
        t("fullC", "Full Body C", [("front-squat", 3, 6), ("incline-dumbbell-press", 3, 10), ("seated-cable-row", 3, 10),
                                   ("romanian-deadlift", 3, 8), ("hanging-knee-raise", 3, 12)]),
        t("machine", "Machine Circuit", [("machine-chest-press", 3, 10), ("lat-pulldown", 3, 10), ("leg-press", 3, 10),
                                         ("machine-seated-row", 3, 10), ("machine-shoulder-press", 3, 10), ("seated-leg-curl", 3, 12)]),
    ]
}

/// A weekly split: seven slots, each a template id or a rest day, laid out from a chosen start day.
struct SplitPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    /// Exactly seven entries; nil is a rest day. Slot 0 falls on the chosen start day.
    let cycle: [String?]

    var sessionsPerWeek: Int { cycle.compactMap { $0 }.count }
    var templateIDs: [String] {
        var seen: [String] = []
        for id in cycle.compactMap({ $0 }) where !seen.contains(id) { seen.append(id) }
        return seen
    }

    /// Template id (or nil for rest) for each weekday 0 = Monday … 6 = Sunday.
    func layout(startingOn start: Int) -> [Int: String?] {
        var result: [Int: String?] = [:]
        for (offset, slot) in cycle.enumerated() {
            result[(start + offset) % 7] = .some(slot)
        }
        return result
    }

    /// The start day that puts the first session on the earliest preferred day, or Monday.
    static func suggestedStart(preferred: [Int]) -> Int { preferred.min() ?? 0 }

    static func recommended(forDays count: Int, experience: ExperienceLevel) -> String {
        if experience == .new { return count >= 3 ? "machine3" : "full2" }
        switch count {
        case ...2: return "full2"
        case 3: return "full3"
        case 4: return "ul4"
        case 5: return "pplul"
        default: return "ppl"
        }
    }

    static let all: [SplitPreset] = [
        SplitPreset(id: "ppl", name: "Push / Pull / Legs", summary: "Three focused sessions, a rest day, then the three again.",
                    symbol: "arrow.triangle.2.circlepath", cycle: ["push", "pull", "legs", nil, "push", "pull", "legs"]),
        SplitPreset(id: "ppl3", name: "PPL · 3 days", summary: "Each session once a week with rest days in between.",
                    symbol: "3.circle", cycle: ["push", nil, "pull", nil, "legs", nil, nil]),
        SplitPreset(id: "ppl5", name: "PPL · 5 days", summary: "Push and pull twice, legs once, two rest days.",
                    symbol: "5.circle", cycle: ["push", "pull", "legs", nil, "push", "pull", nil]),
        SplitPreset(id: "ppl6", name: "PPL · 6 days", summary: "Every session twice a week with one full rest day.",
                    symbol: "6.circle", cycle: ["push", "pull", "legs", "push", "pull", "legs", nil]),
        SplitPreset(id: "arnold", name: "Arnold Split", summary: "Chest & back, shoulders & arms, legs, then repeat after a rest.",
                    symbol: "figure.strengthtraining.traditional", cycle: ["chestBack", "shouldersArms", "legs", nil, "chestBack", "shouldersArms", "legs"]),
        SplitPreset(id: "ul3", name: "Upper / Lower", summary: "Alternating upper and lower sessions with a rest day after each.",
                    symbol: "arrow.up.arrow.down", cycle: ["upper", nil, "lower", nil, "upper", nil, nil]),
        SplitPreset(id: "ul4", name: "Upper / Lower / Upper / Lower", summary: "Four sessions: upper and lower body twice each.",
                    symbol: "arrow.up.arrow.down.circle", cycle: ["upper", "lower", nil, "upper", "lower", nil, nil]),
        SplitPreset(id: "pplul", name: "Push / Pull / Legs / Upper / Lower", summary: "Five sessions combining PPL with an upper/lower pair.",
                    symbol: "square.stack.3d.up", cycle: ["push", "pull", "legs", nil, "upper", "lower", nil]),
        SplitPreset(id: "arnoldPPL", name: "Arnold + PPL", summary: "Six sessions: an Arnold block followed by push, pull, legs.",
                    symbol: "bolt.horizontal", cycle: ["chestBack", "shouldersArms", "legs", nil, "push", "pull", "legs"]),
        SplitPreset(id: "bro", name: "Bro Split", summary: "One muscle group per day across five days.",
                    symbol: "list.number", cycle: ["chest", "back", "shoulders", "arms", "legs", nil, nil]),
        SplitPreset(id: "full3", name: "Full Body · 3 days", summary: "Three different whole-body sessions with rest between.",
                    symbol: "figure.cross.training", cycle: ["fullA", nil, "fullB", nil, "fullC", nil, nil]),
        SplitPreset(id: "full2", name: "Full Body · 2 days", summary: "Two whole-body sessions for a busy week.",
                    symbol: "2.circle", cycle: ["fullA", nil, nil, "fullB", nil, nil, nil]),
        SplitPreset(id: "machine3", name: "Machine Starter", summary: "Guided machines three times a week while you learn the movements.",
                    symbol: "gearshape.2", cycle: ["machine", nil, "machine", nil, "machine", nil, nil]),
    ]

    static func find(_ id: String) -> SplitPreset? { all.first { $0.id == id } }
}
