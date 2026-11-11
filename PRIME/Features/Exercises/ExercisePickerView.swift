import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    enum Mode { case single, multiple }

    let mode: Mode
    var title = "Choose exercise"
    var excluding: Set<String> = []
    let onPick: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingStore.self) private var store
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var filter = ExerciseFilter()
    @State private var selected: [Exercise] = []
    @State private var recentOnly = false

    private var results: [Exercise] {
        var items = filter.apply(to: exercises.filter { !excluding.contains($0.slug) })
        if recentOnly {
            let recent = store.history.exerciseSlugsByRecency
            let order = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            items = items.filter { order[$0.slug] != nil }.sorted { (order[$0.slug] ?? 0) < (order[$1.slug] ?? 0) }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !store.history.isEmpty {
                            Chip(title: "Recent", symbol: "clock", isSelected: recentOnly) { recentOnly.toggle() }
                        }
                        Chip(title: "Favourites", symbol: "star.fill", isSelected: filter.favouritesOnly) { filter.favouritesOnly.toggle() }
                        ForEach(MuscleGroup.allCases) { muscle in
                            Chip(title: muscle.shortName, isSelected: filter.muscles.contains(muscle)) {
                                if filter.muscles.contains(muscle) { filter.muscles.remove(muscle) } else { filter.muscles.insert(muscle) }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 10)
                }
                List(results) { exercise in
                    let isSelected = selected.contains { $0.slug == exercise.slug }
                    Button {
                        Haptics.selection()
                        if mode == .single {
                            onPick([exercise])
                            dismiss()
                        } else if isSelected {
                            selected.removeAll { $0.slug == exercise.slug }
                        } else {
                            selected.append(exercise)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseIllustration(exercise: exercise, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text("\(exercise.primaryMuscleSummary) · \(exercise.equipment.displayName)")
                                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if mode == .multiple {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if results.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Try a different search or clear the filters.")
                    }
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises or muscles")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if mode == .multiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selected.isEmpty ? "Add" : "Add (\(selected.count))") {
                            onPick(selected)
                            dismiss()
                        }
                        .fontWeight(.bold)
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }
}
