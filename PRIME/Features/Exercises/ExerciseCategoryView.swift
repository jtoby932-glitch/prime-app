import SwiftData
import SwiftUI

/// A filtered exercise list: one muscle group, one kind of equipment, favourites or everything.
struct ExerciseCategoryView: View {
    enum Scope: Hashable {
        case muscle(MuscleGroup), equipment(Equipment), favourites, all

        var title: String {
            switch self {
            case .muscle(let muscle): return muscle.displayName
            case .equipment(let item): return item.displayName
            case .favourites: return "Favourites"
            case .all: return "All exercises"
            }
        }
    }

    let scope: Scope
    @Environment(\.bodyModel) private var model
    @Environment(\.motion) private var motion
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var filter = ExerciseFilter()
    @State private var difficulty: Difficulty?
    @State private var showFilters = false

    private var base: [Exercise] {
        switch scope {
        case .muscle(let muscle): return exercises.filter { $0.primaryMuscles.contains(muscle) }
        case .equipment(let item): return exercises.filter { $0.equipment == item }
        case .favourites: return exercises.filter(\.isFavourite)
        case .all: return exercises
        }
    }

    private var results: [Exercise] {
        filter.apply(to: base).filter { difficulty == nil || $0.difficulty == difficulty }
    }

    private var secondary: [Exercise] {
        guard case .muscle(let muscle) = scope, !filter.isActive, difficulty == nil else { return [] }
        return exercises.filter { $0.secondaryMuscles.contains(muscle) && !$0.primaryMuscles.contains(muscle) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if case .muscle(let muscle) = scope { muscleHeader(muscle) }
                filterBar
                if results.isEmpty {
                    EmptyStateView(symbol: scope == .favourites ? "star" : "line.3.horizontal.decrease.circle",
                                   title: scope == .favourites ? "No favourites yet" : "No exercises match",
                                   message: scope == .favourites ? "Tap the star on any exercise to add it here." : "Try removing a filter.",
                                   actionTitle: filter.activeFilterCount > 0 || difficulty != nil ? "Clear filters" : nil) {
                        filter = ExerciseFilter()
                        difficulty = nil
                    }
                    .primeCard()
                } else {
                    Text("\(results.count) exercise\(results.count == 1 ? "" : "s")").eyebrow()
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.slug) { index, exercise in
                            NavigationLink(value: Route.exercise(exercise.slug)) {
                                ExerciseRow(exercise: exercise, showsMuscles: !isMuscleScope)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(PressableStyle())
                            .appear(min(index, 10))
                            if index < results.count - 1 { DividerLine().padding(.leading, 60) }
                        }
                    }
                    .primeCard(padding: 12)
                }
                if !secondary.isEmpty {
                    SectionHeader(title: "Also works it", subtitle: "Exercises where this muscle assists")
                    VStack(spacing: 0) {
                        ForEach(secondary) { exercise in
                            NavigationLink(value: Route.exercise(exercise.slug)) { ExerciseRow(exercise: exercise).padding(.vertical, 8) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .primeCard(padding: 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .animation(motion.animation(), value: results.map(\.slug))
        }
        .scrollDismissesKeyboard(.interactively)
        .primeBackground()
        .searchable(text: $filter.query, prompt: "Search \(scope.title.lowercased())")
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showFilters) {
            ExerciseFilterSheet(filter: $filter, difficulty: $difficulty, showMuscles: !isMuscleScope, showEquipment: !isEquipmentScope)
                .presentationDetents([.medium, .large])
        }
    }

    private var isMuscleScope: Bool { if case .muscle = scope { return true } else { return false } }
    private var isEquipmentScope: Bool { if case .equipment = scope { return true } else { return false } }

    private func muscleHeader(_ muscle: MuscleGroup) -> some View {
        let info = MuscleInfo.of(muscle)
        let figure = AnatomyFigure.figure(model)
        return HStack(spacing: 14) {
            AnatomyCanvas(side: figure.bestSide(for: [muscle]), primary: [muscle], model: model)
                .frame(width: 64, height: 128)
            VStack(alignment: .leading, spacing: 6) {
                Text(info.anatomicalName).font(.caption.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                Text(info.function).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: Route.muscle(muscle)) {
                    Label("Open in muscle explorer", systemImage: "figure.arms.open").font(.caption.weight(.semibold))
                }
            }
        }
        .primeCard(padding: 14)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Filters", symbol: "line.3.horizontal.decrease", isSelected: filter.activeFilterCount > 0 || difficulty != nil,
                     count: (filter.activeFilterCount + (difficulty == nil ? 0 : 1)).nonZero) { showFilters = true }
                ForEach(Mechanic.allCases) { mechanic in
                    Chip(title: mechanic.displayName, isSelected: filter.mechanic == mechanic) {
                        filter.mechanic = filter.mechanic == mechanic ? nil : mechanic
                    }
                }
                ForEach(Difficulty.allCases) { level in
                    Chip(title: level.displayName, isSelected: difficulty == level) {
                        difficulty = difficulty == level ? nil : level
                    }
                }
            }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

struct ExerciseFilterSheet: View {
    @Binding var filter: ExerciseFilter
    @Binding var difficulty: Difficulty?
    var showMuscles = true
    var showEquipment = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if showMuscles {
                    Section("Muscle group") {
                        flow(MuscleGroup.allCases, title: \.displayName, isOn: { filter.muscles.contains($0) }) { muscle in
                            if filter.muscles.contains(muscle) { filter.muscles.remove(muscle) } else { filter.muscles.insert(muscle) }
                        }
                        Toggle("Include secondary muscles", isOn: $filter.includeSecondary)
                    }
                }
                if showEquipment {
                    Section("Equipment") {
                        flow(Equipment.allCases, title: \.displayName, isOn: { filter.equipment.contains($0) }) { item in
                            if filter.equipment.contains(item) { filter.equipment.remove(item) } else { filter.equipment.insert(item) }
                        }
                    }
                }
                Section("Type") {
                    Picker("Type", selection: $filter.mechanic) {
                        Text("Any").tag(Mechanic?.none)
                        ForEach(Mechanic.allCases) { Text($0.displayName).tag(Mechanic?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Any").tag(Difficulty?.none)
                        ForEach(Difficulty.allCases) { Text($0.displayName).tag(Difficulty?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Favourites only", isOn: $filter.favouritesOnly)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        let query = filter.query
                        filter = ExerciseFilter()
                        filter.query = query
                        difficulty = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func flow<T: Identifiable>(_ items: [T], title: KeyPath<T, String>, isOn: @escaping (T) -> Bool, toggle: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Chip(title: item[keyPath: title], isSelected: isOn(item)) { toggle(item) }
            }
        }
        .padding(.vertical, 6)
    }
}
