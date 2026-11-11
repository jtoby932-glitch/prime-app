import SwiftData
import SwiftUI

/// Create or edit a user's own exercise. Custom exercises use the user's own tiers or stay unranked.
struct CustomExerciseEditor: View {
    var existing: Exercise? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]

    @State private var name = ""
    @State private var primary: Set<MuscleGroup> = []
    @State private var secondary: Set<MuscleGroup> = []
    @State private var equipment: Equipment = .dumbbell
    @State private var mechanic: Mechanic = .compound
    @State private var difficulty: Difficulty = .beginner
    @State private var instructions = ""
    @State private var tips = ""
    @State private var ranked = false
    @State private var thresholdTexts = ["", "", "", ""]
    @State private var errors: [String] = []
    @State private var loaded = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var method: RankingMethod {
        switch equipment {
        case .bodyweight: return .repetitions
        case .band: return .unranked
        default: return .relativeLoad
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Type", selection: $mechanic) {
                        ForEach(Mechanic.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Primary muscles") { muscleGrid(selection: $primary, other: secondary) }
                Section("Secondary muscles") { muscleGrid(selection: $secondary, other: primary) }
                Section {
                    TextField("One step per line", text: $instructions, axis: .vertical).lineLimit(3...8)
                } header: { Text("Instructions (optional)") }
                Section {
                    TextField("One tip per line", text: $tips, axis: .vertical).lineLimit(2...6)
                } header: { Text("Technique notes (optional)") }

                if method != .unranked {
                    Section {
                        Toggle("Rank this exercise", isOn: $ranked)
                        if ranked {
                            ForEach(1..<5, id: \.self) { index in
                                let tier = RankTier(rawValue: index) ?? .bronze
                                HStack {
                                    TierBadgeView(tier: tier, size: 22)
                                    Text(tier.name)
                                    Spacer()
                                    TextField(method == .relativeLoad ? "× BW" : "reps", text: $thresholdTexts[index - 1])
                                        .keyboardType(method == .relativeLoad ? .decimalPad : .numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 90)
                                }
                            }
                        }
                    } header: { Text("Your tiers") } footer: {
                        Text(method == .relativeLoad
                             ? "Enter the estimated 1RM ÷ bodyweight needed for each tier, e.g. 1.0 means lifting your bodyweight. PRIME has no data for custom exercises, so these are yours to set."
                             : "Enter the reps in one set needed for each tier.")
                    }
                } else {
                    Section { Text("Band exercises aren't ranked because band tension varies.").foregroundStyle(Theme.textSecondary) }
                }

                if !errors.isEmpty {
                    Section { ForEach(errors, id: \.self) { InlineError(message: $0) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
            .onAppear(perform: load)
        }
    }

    private func muscleGrid(selection: Binding<Set<MuscleGroup>>, other: Set<MuscleGroup>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(MuscleGroup.allCases) { muscle in
                Chip(title: muscle.shortName, isSelected: selection.wrappedValue.contains(muscle)) {
                    if selection.wrappedValue.contains(muscle) {
                        selection.wrappedValue.remove(muscle)
                    } else if !other.contains(muscle) {
                        selection.wrappedValue.insert(muscle)
                    }
                }
                .opacity(other.contains(muscle) ? 0.35 : 1)
            }
        }
        .padding(.vertical, 6)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        primary = Set(existing.primaryMuscles)
        secondary = Set(existing.secondaryMuscles)
        equipment = existing.equipment
        mechanic = existing.mechanic
        difficulty = existing.difficulty
        instructions = existing.instructions.joined(separator: "\n")
        tips = existing.techniqueTips.joined(separator: "\n")
        if let thresholds = existing.customThresholds, RankingStandard.isValid(thresholds) {
            ranked = true
            thresholdTexts = thresholds.map { Format.number($0) }
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        var problems: [String] = []
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { problems.append("Give the exercise a name.") }
        if exercises.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.slug != existing?.slug }) {
            problems.append("An exercise with that name already exists.")
        }
        if primary.isEmpty { problems.append("Choose at least one primary muscle.") }
        var thresholds: [Double]?
        if ranked && method != .unranked {
            let values = thresholdTexts.map { InputValidator.parseNumber($0) }
            if values.contains(where: { $0 == nil }) {
                problems.append("Enter a number for every tier.")
            } else {
                let numbers = values.compactMap { $0 }
                if RankingStandard.isValid(numbers) { thresholds = numbers } else { problems.append("Each tier must be higher than the one before it.") }
            }
        }
        guard problems.isEmpty else {
            withAnimation { errors = problems }
            Haptics.error()
            return
        }
        let exercise: Exercise
        if let existing {
            exercise = existing
        } else {
            exercise = Exercise(slug: "custom-" + UUID().uuidString.lowercased(), name: trimmed)
            exercise.isCustom = true
            context.insert(exercise)
        }
        exercise.name = trimmed
        exercise.primaryMuscles = MuscleGroup.allCases.filter { primary.contains($0) }
        exercise.secondaryMuscles = MuscleGroup.allCases.filter { secondary.contains($0) }
        exercise.equipment = equipment
        exercise.mechanic = mechanic
        exercise.difficulty = difficulty
        exercise.instructions = lines(instructions)
        exercise.techniqueTips = lines(tips)
        exercise.rankingMethod = thresholds == nil ? .unranked : method
        exercise.defaultThresholds = []
        exercise.customThresholds = thresholds
        exercise.rankingNote = thresholds == nil ? "" : "Your own tiers."
        for entry in exercise.plannedEntries { entry.exerciseName = trimmed }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
