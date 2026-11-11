import SwiftData
import SwiftUI

struct ExercisesView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var filter = ExerciseFilter()
    @State private var showFilters = false
    @State private var showCreator = false

    private var results: [Exercise] { filter.apply(to: exercises) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Route.muscleMap) {
                        HStack(spacing: 14) {
                            AnatomyCanvas(side: .front, intensity: [.chest: 1, .quadriceps: 0.6, .abdominals: 0.3], showDetail: false)
                                .frame(width: 44, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Muscle map").font(.headline).foregroundStyle(.white)
                                Text("Tap a muscle to find exercises for it").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    filterBar
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(results) { exercise in
                        NavigationLink(value: Route.exercise(exercise.slug)) {
                            ExerciseRow(exercise: exercise)
                        }
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            Button {
                                exercise.isFavourite.toggle()
                                Haptics.selection()
                            } label: {
                                Label(exercise.isFavourite ? "Unfavourite" : "Favourite", systemImage: exercise.isFavourite ? "star.slash" : "star.fill")
                            }
                            .tint(Theme.warning)
                        }
                    }
                } header: {
                    Text("\(results.count) exercise\(results.count == 1 ? "" : "s")")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .primeBackground()
            .overlay {
                if results.isEmpty && !exercises.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No exercises match",
                                   message: "Try another search, or create your own exercise.",
                                   actionTitle: "Clear filters") { filter = ExerciseFilter() }
                }
            }
            .searchable(text: $filter.query, prompt: "Search name, muscle or equipment")
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreator = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create exercise")
                }
            }
            .sheet(isPresented: $showFilters) {
                ExerciseFilterSheet(filter: $filter).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCreator) { CustomExerciseEditor() }
            .primeDestinations()
            .workoutBarInset()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: filter.activeFilterCount > 0 ? "Filters · \(filter.activeFilterCount)" : "Filters",
                     symbol: "line.3.horizontal.decrease", isSelected: filter.activeFilterCount > 0) { showFilters = true }
                Chip(title: "Favourites", symbol: "star.fill", isSelected: filter.favouritesOnly) { filter.favouritesOnly.toggle() }
                ForEach(MuscleGroup.allCases) { muscle in
                    Chip(title: muscle.shortName, isSelected: filter.muscles.contains(muscle)) {
                        if filter.muscles.contains(muscle) { filter.muscles.remove(muscle) } else { filter.muscles.insert(muscle) }
                        Haptics.selection()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseIllustration(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    if exercise.isFavourite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.warning).accessibilityLabel("Favourite")
                    }
                    if exercise.isCustom { Tag(text: "Custom", color: Theme.info) }
                }
                Text("\(exercise.primaryMuscleSummary) · \(exercise.equipment.displayName)")
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseFilterSheet: View {
    @Binding var filter: ExerciseFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Muscle group") {
                    flow(MuscleGroup.allCases, title: \.displayName, isOn: { filter.muscles.contains($0) }) { muscle in
                        if filter.muscles.contains(muscle) { filter.muscles.remove(muscle) } else { filter.muscles.insert(muscle) }
                    }
                    Toggle("Include secondary muscles", isOn: $filter.includeSecondary)
                }
                Section("Equipment") {
                    flow(Equipment.allCases, title: \.displayName, isOn: { filter.equipment.contains($0) }) { item in
                        if filter.equipment.contains(item) { filter.equipment.remove(item) } else { filter.equipment.insert(item) }
                    }
                }
                Section("Type") {
                    Picker("Type", selection: $filter.mechanic) {
                        Text("Any").tag(Mechanic?.none)
                        ForEach(Mechanic.allCases) { Text($0.displayName).tag(Mechanic?.some($0)) }
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
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.bold) }
            }
        }
    }

    private func flow<T: Identifiable>(_ items: [T], title: KeyPath<T, String>, isOn: @escaping (T) -> Bool, toggle: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Chip(title: item[keyPath: title], isSelected: isOn(item)) {
                    toggle(item)
                    Haptics.selection()
                }
            }
        }
        .padding(.vertical, 6)
    }
}
