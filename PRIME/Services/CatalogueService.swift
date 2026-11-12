import Foundation
import SwiftData

/// The bundled exercise database. New exercises are added by editing `exercises.json`
/// and bumping its version — no code changes needed.
struct ExerciseCatalogue: Codable {
    struct Ranking: Codable {
        var method: String
        var thresholds: [Double]
        var note: String?
    }

    struct Entry: Codable, Identifiable {
        var slug: String
        var name: String
        var primary: [String]
        var secondary: [String]
        var equipment: String
        var mechanic: String
        var difficulty: String
        var instructions: [String]?
        var tips: [String]?
        var mistakes: [String]?
        var alternatives: [String]
        var ranking: Ranking?
        var guide: ExerciseGuide?
        var id: String { slug }
    }

    var version: Int
    var exercises: [Entry]
}

enum CatalogueError: LocalizedError {
    case missingResource
    var errorDescription: String? { "The exercise database is missing from the app bundle." }
}

@MainActor
enum CatalogueService {
    static let versionKey = "prime.catalogueVersion"

    static func loadBundled(bundle: Bundle = .main) throws -> ExerciseCatalogue {
        guard let url = bundle.url(forResource: "exercises", withExtension: "json") else { throw CatalogueError.missingResource }
        let data = try Data(contentsOf: url)
        let catalogue = try JSONDecoder().decode(ExerciseCatalogue.self, from: data)
        ExerciseLibrary.shared.install(catalogue)
        return catalogue
    }

    /// Inserts new catalogue exercises and refreshes the text of existing ones, keeping
    /// favourites, custom thresholds and every custom exercise untouched.
    @discardableResult
    static func seedIfNeeded(context: ModelContext, catalogue: ExerciseCatalogue? = nil, defaults: UserDefaults = .standard, force: Bool = false) throws -> Int {
        let catalogue = try catalogue ?? loadBundled()
        let storedCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        let seededVersion = defaults.integer(forKey: versionKey)
        guard force || storedCount == 0 || seededVersion < catalogue.version else { return 0 }

        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var bySlug: [String: Exercise] = [:]
        for exercise in existing { bySlug[exercise.slug] = exercise }

        var inserted = 0
        for entry in catalogue.exercises {
            if let exercise = bySlug[entry.slug] {
                if !exercise.isCustom && (force || exercise.catalogueVersion < catalogue.version) {
                    apply(entry, to: exercise, version: catalogue.version)
                }
            } else {
                let exercise = Exercise(slug: entry.slug, name: entry.name)
                apply(entry, to: exercise, version: catalogue.version)
                context.insert(exercise)
                bySlug[entry.slug] = exercise
                inserted += 1
            }
        }
        try context.save()
        defaults.set(catalogue.version, forKey: versionKey)
        return inserted
    }

    static func apply(_ entry: ExerciseCatalogue.Entry, to exercise: Exercise, version: Int) {
        exercise.name = entry.name
        exercise.primaryMusclesRaw = entry.primary.filter { MuscleGroup(rawValue: $0) != nil }
        exercise.secondaryMusclesRaw = entry.secondary.filter { MuscleGroup(rawValue: $0) != nil }
        exercise.equipmentRaw = Equipment(rawValue: entry.equipment)?.rawValue ?? Equipment.machine.rawValue
        exercise.mechanicRaw = Mechanic(rawValue: entry.mechanic)?.rawValue ?? Mechanic.compound.rawValue
        exercise.difficultyRaw = Difficulty(rawValue: entry.difficulty)?.rawValue ?? Difficulty.beginner.rawValue
        exercise.instructions = entry.guide?.steps ?? entry.instructions ?? []
        exercise.techniqueTips = entry.guide?.form ?? entry.tips ?? []
        exercise.commonMistakes = entry.guide?.mistakes.map(\.what) ?? entry.mistakes ?? []
        exercise.alternativeSlugs = entry.alternatives
        if let ranking = entry.ranking, let method = RankingMethod(rawValue: ranking.method),
           method == .unranked || RankingStandard.isValid(ranking.thresholds) {
            exercise.rankingMethodRaw = method.rawValue
            exercise.defaultThresholds = method == .unranked ? [] : ranking.thresholds
            exercise.rankingNote = ranking.note ?? ""
        } else {
            exercise.rankingMethodRaw = RankingMethod.unranked.rawValue
            exercise.defaultThresholds = []
            exercise.rankingNote = ""
        }
        exercise.catalogueVersion = version
        exercise.isCustom = false
    }
}
