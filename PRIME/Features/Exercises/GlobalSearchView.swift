import SwiftData
import SwiftUI

/// Search everything from one place: exercises, muscle groups, routines and past workouts.
struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchSuggestions(query: $query)
                    } else {
                        SearchResultsList(query: query)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .primeBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Exercises, muscles, routines, workouts")
            .onSubmit(of: .search) { profiles.first?.noteSearch(query) }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .primeDestinations()
        }
    }
}

struct SearchSuggestions: View {
    @Binding var query: String
    @Query private var profiles: [UserProfile]

    private static let suggestions = ["Bench press", "Squat", "Back", "Dumbbell", "Glutes", "Cable", "Core", "Pull-up"]

    var body: some View {
        let recent = profiles.first?.recentSearches ?? []
        VStack(alignment: .leading, spacing: 18) {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent searches").eyebrow()
                        Spacer()
                        Button("Clear") { profiles.first?.recentSearches = [] }
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                    }
                    ForEach(recent, id: \.self) { text in
                        Button { query = text } label: {
                            Label(text, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Try").eyebrow()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { text in
                        Chip(title: text, symbol: "magnifyingglass") { query = text }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Grouped results for a query. Matching is case- and accent-insensitive, every word must match.
struct SearchResultsList: View {
    let query: String
    @Environment(TrainingStore.self) private var store
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutPlan.name) private var plans: [WorkoutPlan]
    @Query private var profiles: [UserProfile]

    private var words: [String] { ExerciseFilter.normalise(query).split(separator: " ").map(String.init) }

    private func matches(_ text: String) -> Bool {
        let haystack = ExerciseFilter.normalise(text)
        return words.allSatisfy { haystack.contains($0) }
    }

    var body: some View {
        let exerciseHits = ExerciseFilter(query: query).apply(to: exercises)
        let muscleHits = MuscleGroup.allCases.filter { matches($0.displayName + " " + $0.shortName + " " + MuscleInfo.of($0).anatomicalName) }
        let planHits = plans.filter { matches($0.name + " " + $0.sortedEntries.map(\.exerciseName).joined(separator: " ")) }
        let matchedSlugs = Set(exerciseHits.map(\.slug))
        let sessionsWithExercise = Set(matchedSlugs.flatMap { store.history.samples(for: $0).map(\.sessionID) })
        let sessionHits = store.history.sessions.filter { matches($0.name) || sessionsWithExercise.contains($0.id) }
        let unit = profiles.first?.weightUnit ?? .kg

        VStack(alignment: .leading, spacing: 18) {
            if exerciseHits.isEmpty && muscleHits.isEmpty && planHits.isEmpty && sessionHits.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Nothing found for “\(query)”",
                               message: "Try a muscle (\"hamstrings\"), equipment (\"cable\") or part of a name.")
            }
            if !muscleHits.isEmpty {
                group("Muscle groups") {
                    ForEach(muscleHits) { muscle in
                        NavigationLink(value: Route.category(muscle)) {
                            HStack {
                                Label(muscle.displayName, systemImage: "figure.arms.open").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(exercises.filter { $0.primaryMuscles.contains(muscle) }.count)").font(.caption).foregroundStyle(Theme.textSecondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            if !exerciseHits.isEmpty {
                group("Exercises · \(exerciseHits.count)") {
                    ForEach(exerciseHits.prefix(30)) { exercise in
                        NavigationLink(value: Route.exercise(exercise.slug)) { ExerciseRow(exercise: exercise).padding(.vertical, 6) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
            if !planHits.isEmpty {
                group("Routines") {
                    ForEach(planHits) { plan in
                        NavigationLink(value: Route.plan(plan.uuid)) {
                            HStack {
                                Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 8, height: 8)
                                Text(plan.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(plan.entries.count) exercises").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            if !sessionHits.isEmpty {
                group("Past workouts") {
                    ForEach(sessionHits.prefix(15)) { session in
                        NavigationLink(value: Route.session(session.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Text(session.startedAt.relativeDayText + " · \(session.setCount) sets · " + Format.volume(session.volume, unit: unit))
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow()
            VStack(alignment: .leading, spacing: 0) { content() }
                .primeCard(padding: 12)
        }
    }
}
