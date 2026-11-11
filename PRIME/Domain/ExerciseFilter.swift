import Foundation

/// Anything that can be searched and filtered like an exercise.
protocol ExerciseDescribing {
    var displayName: String { get }
    var primaryMuscles: [MuscleGroup] { get }
    var secondaryMuscles: [MuscleGroup] { get }
    var equipment: Equipment { get }
    var mechanic: Mechanic { get }
    var difficulty: Difficulty { get }
    var favourite: Bool { get }
}

struct ExerciseFilter: Equatable {
    var query: String = ""
    var muscles: Set<MuscleGroup> = []
    var equipment: Set<Equipment> = []
    var mechanic: Mechanic? = nil
    var favouritesOnly: Bool = false
    /// When on, a muscle filter also matches exercises that only work it secondarily.
    var includeSecondary: Bool = false

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || !muscles.isEmpty || !equipment.isEmpty || mechanic != nil || favouritesOnly
    }

    var activeFilterCount: Int {
        muscles.count + equipment.count + (mechanic == nil ? 0 : 1) + (favouritesOnly ? 1 : 0)
    }

    func matches(_ item: some ExerciseDescribing) -> Bool {
        if favouritesOnly && !item.favourite { return false }
        if let mechanic, item.mechanic != mechanic { return false }
        if !equipment.isEmpty && !equipment.contains(item.equipment) { return false }
        if !muscles.isEmpty {
            let pool = includeSecondary ? item.primaryMuscles + item.secondaryMuscles : item.primaryMuscles
            if muscles.isDisjoint(with: pool) { return false }
        }
        return matchesQuery(item)
    }

    /// Every word typed must appear in the name, a muscle or the equipment. Case and accent insensitive.
    func matchesQuery(_ item: some ExerciseDescribing) -> Bool {
        let words = Self.normalise(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = Self.normalise(
            ([item.displayName, item.equipment.displayName, item.equipment.rawValue, item.mechanic.displayName]
             + (item.primaryMuscles + item.secondaryMuscles).flatMap { [$0.displayName, $0.shortName] })
                .joined(separator: " ")
        )
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Filters and sorts: name matches first, then alphabetical.
    func apply<T: ExerciseDescribing>(to items: [T]) -> [T] {
        let filtered = items.filter { matches($0) }
        let words = Self.normalise(query)
        guard !words.isEmpty else {
            return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return filtered.sorted { a, b in
            let aStarts = Self.normalise(a.displayName).hasPrefix(words)
            let bStarts = Self.normalise(b.displayName).hasPrefix(words)
            if aStarts != bStarts { return aStarts }
            let aName = Self.normalise(a.displayName).contains(words)
            let bName = Self.normalise(b.displayName).contains(words)
            if aName != bName { return aName }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    static func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
