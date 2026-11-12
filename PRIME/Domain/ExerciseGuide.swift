import Foundation

/// Structured technique guide for one exercise, bundled in exercises.json.
struct ExerciseGuide: Codable, Equatable {
    struct Mistake: Codable, Equatable, Hashable {
        /// What the mistake looks like.
        let what: String
        /// Why it reduces movement quality or adds strain.
        let why: String
        /// How to correct it.
        let fix: String
    }

    var overview: String
    var setup: [String]
    var steps: [String]
    var form: [String]
    var breathing: String
    var mistakes: [Mistake]
    var safety: [String]
    var easier: [String]
    var harder: [String]
    var pattern: String
    var unilateral: Bool
    var tracking: TrackingType

    static let empty = ExerciseGuide(overview: "", setup: [], steps: [], form: [], breathing: "", mistakes: [], safety: [],
                                     easier: [], harder: [], pattern: "", unilateral: false, tracking: .weightReps)

    var hasContent: Bool { !setup.isEmpty || !steps.isEmpty }
}

/// Read-only lookup of bundled guides by exercise slug. Loaded once, off the database.
final class ExerciseLibrary {
    static let shared = ExerciseLibrary()

    private(set) var guides: [String: ExerciseGuide] = [:]
    private var loaded = false

    func load(bundle: Bundle = .main) {
        guard !loaded else { return }
        loaded = true
        guard let url = bundle.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalogue = try? JSONDecoder().decode(ExerciseCatalogue.self, from: data) else { return }
        install(catalogue)
    }

    func install(_ catalogue: ExerciseCatalogue) {
        var map: [String: ExerciseGuide] = [:]
        for entry in catalogue.exercises { if let guide = entry.guide { map[entry.slug] = guide } }
        guides = map
        loaded = true
    }

    func guide(for slug: String) -> ExerciseGuide? {
        load()
        return guides[slug]
    }

    func tracking(for slug: String) -> TrackingType {
        guide(for: slug)?.tracking ?? .weightReps
    }

    func isTimed(_ slug: String) -> Bool { tracking(for: slug) == .time }

    var timedSlugs: Set<String> {
        load()
        return Set(guides.filter { $0.value.tracking == .time }.keys)
    }
}
