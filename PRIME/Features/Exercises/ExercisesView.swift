import SwiftData
import SwiftUI

struct ExercisesView: View {
    @Environment(\.bodyModel) private var model
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var query = ""
    @State private var showCreator = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        browse
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
            .onSubmit(of: .search) { profile?.noteSearch(query) }
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreator = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create exercise")
                }
            }
            .sheet(isPresented: $showCreator) { CustomExerciseEditor() }
            .primeDestinations()
        }
    }

    @ViewBuilder
    private var browse: some View {
        NavigationLink(value: Route.muscleMap) { explorerBanner }.buttonStyle(PressableStyle()).appear(0)

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Browse by muscle", subtitle: "\(exercises.count) exercises")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(MuscleGroup.allCases.enumerated()), id: \.element) { index, muscle in
                    NavigationLink(value: Route.category(muscle)) {
                        CategoryCard(muscle: muscle, count: exercises.filter { $0.primaryMuscles.contains(muscle) }.count, model: model)
                    }
                    .buttonStyle(PressableStyle())
                    .appear(min(index, 8) + 1)
                }
            }
        }

        let recent = (profile?.recentExerciseSlugs ?? []).compactMap { slug in exercises.first { $0.slug == slug } }
        if !recent.isEmpty {
            ExerciseShelf(title: "Recently viewed", exercises: recent)
        }

        let favourites = exercises.filter(\.isFavourite)
        if favourites.isEmpty {
            HStack(spacing: 12) {
                IconBubble(symbol: "star", tint: Theme.warning, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No favourites yet").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Tap the star on any exercise to keep it here.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .primeCard(padding: 12)
        } else {
            ExerciseShelf(title: "Favourites", exercises: favourites, seeAll: .favourites)
        }

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By equipment")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Equipment.allCases) { item in
                        NavigationLink(value: Route.equipment(item)) {
                            EquipmentPill(equipment: item, count: exercises.filter { $0.equipment == item }.count)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            NavigationLink(value: Route.allExercises) {
                HStack {
                    Label("All exercises", systemImage: "list.bullet").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(exercises.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
                .primeCard(padding: 14)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var explorerBanner: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                AnatomyCanvas(side: .front, primary: [.chest, .abdominals, .quadriceps], secondary: [.shoulders], model: model).frame(width: 46, height: 92)
                AnatomyCanvas(side: .back, primary: [.back, .glutes, .hamstrings], secondary: [.traps], model: model).frame(width: 46, height: 92)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Muscle explorer").font(.primeHeadline).foregroundStyle(Theme.textPrimary)
                Text("Tap any muscle to see what it does and the exercises that train it.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 14, highlight: Theme.accent)
    }
}

struct CategoryCard: View {
    let muscle: MuscleGroup
    let count: Int
    let model: BodyModel

    var body: some View {
        let figure = AnatomyFigure.figure(model)
        HStack(spacing: 10) {
            AnatomyCanvas(side: figure.bestSide(for: [muscle]), primary: [muscle], model: model, focus: true)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(count) exercise\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct EquipmentPill: View {
    let equipment: Equipment
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: equipment.symbol).font(.subheadline).foregroundStyle(Theme.accentHighlight)
            Text(equipment.displayName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// A horizontal row of exercise tiles.
struct ExerciseShelf: View {
    let title: String
    let exercises: [Exercise]
    var seeAll: Route? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title)
                if let seeAll {
                    NavigationLink(value: seeAll) { Text("See all").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight) }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exercises.prefix(10)) { exercise in
                        NavigationLink(value: Route.exercise(exercise.slug)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ExerciseIllustration(exercise: exercise, size: 64)
                                Text(exercise.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(width: 104, alignment: .leading)
                            }
                            .padding(10)
                            .frame(width: 124, height: 140, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var showsMuscles = true

    var body: some View {
        HStack(spacing: 12) {
            ExerciseIllustration(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if exercise.isFavourite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.warning).accessibilityLabel("Favourite")
                    }
                    if exercise.isCustom { Tag(text: "Custom", color: Theme.accentHighlight) }
                }
                Text(showsMuscles ? "\(exercise.primaryMuscleSummary) · \(exercise.equipment.displayName)" : "\(exercise.equipment.displayName) · \(exercise.mechanic.displayName) · \(exercise.difficulty.displayName)")
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
