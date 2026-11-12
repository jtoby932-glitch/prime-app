import SwiftData
import SwiftUI
import UIKit

/// Enter a performance for a ranked exercise. Inputs are validated, the rank is fully
/// calculated and stored, and only then does the reveal begin.
struct RankEntryView: View {
    var initialSlug: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var exercise: Exercise?
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var bodyweightText = ""
    @State private var unit: WeightUnit = .kg
    @State private var showPicker = false
    @State private var loaded = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    enum Field { case weight, reps, bodyweight }

    private var scale: Double { profiles.first?.tierScale ?? 1 }
    private var method: RankingMethod { exercise?.rankingMethod ?? .unranked }
    private var needsBodyweight: Bool {
        method == .relativeLoad || (method == .repetitions && (InputValidator.parseNumber(weightText) ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    exerciseButton
                    if let exercise {
                        if exercise.isRanked {
                            inputs(for: exercise)
                            previewCard(for: exercise)
                            Button { submit(exercise) } label: { Label("Reveal my rank", systemImage: "sparkles") }
                                .buttonStyle(.primePrimary)
                                .disabled(!canSubmit)
                            if let failure { InlineError(message: failure) }
                            Text(note(for: exercise)).font(.caption).foregroundStyle(Theme.textTertiary)
                        } else {
                            Text("\(exercise.name) isn't ranked. \(exercise.rankingNote)").font(.subheadline).foregroundStyle(Theme.textSecondary).primeCard()
                        }
                    }
                    Text("You don't need to test a one-rep max: a normal working set of up to \(StrengthMath.reliableRepLimit) reps gives a fair estimate.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .primeBackground()
            .navigationTitle("Log ranked performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView(mode: .single, title: "Choose a ranked exercise", rankedOnly: true) { exercise = $0.first }
            }
            .onAppear(perform: load)
        }
    }

    private var exerciseButton: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 12) {
                if let exercise {
                    ExerciseIllustration(exercise: exercise, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("\(exercise.equipment.displayName) · \(exercise.rankingMethod.metricName)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    IconBubble(symbol: "dumbbell.fill", size: 48)
                    Text("Choose an exercise").font(.headline).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.textTertiary)
            }
            .primeCard(padding: 14)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(exercise.map { "Exercise: \($0.name). Change" } ?? "Choose an exercise")
    }

    private func inputs(for exercise: Exercise) -> some View {
        VStack(spacing: 14) {
            Picker("Units", selection: $unit) {
                ForEach(WeightUnit.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { old, new in convertInputs(from: old, to: new) }
            inputRow(title: exercise.rankingMethod == .repetitions ? "Added weight (optional)" : "Weight", text: $weightText,
                     suffix: unit.symbol, keyboard: .decimalPad, field: .weight, error: weightError)
            inputRow(title: "Reps", text: $repsText, suffix: "reps", keyboard: .numberPad, field: .reps, error: repsError)
            if needsBodyweight {
                inputRow(title: "Bodyweight", text: $bodyweightText, suffix: unit.symbol, keyboard: .decimalPad, field: .bodyweight, error: bodyweightError)
            }
        }
        .primeCard(padding: 16)
    }

    private func inputRow(title: String, text: Binding<String>, suffix: String, keyboard: UIKeyboardType, field: Field, error: ValidationError?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("0", text: text)
                    .keyboardType(keyboard)
                    .focused($focus, equals: field)
                    .multilineTextAlignment(.trailing)
                    .font(.primeNumber(24))
                    .frame(width: 110)
                Text(suffix).font(.subheadline).foregroundStyle(Theme.textSecondary).frame(width: 36, alignment: .leading)
            }
            if let error { InlineError(message: error.errorDescription ?? "Invalid") }
        }
    }

    @ViewBuilder
    private func previewCard(for exercise: Exercise) -> some View {
        if let set = rankableSet(for: exercise) {
            switch RankingEngine.evaluate(set, standard: exercise.rankingStandard, scale: scale) {
            case .success(let result):
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text(result.method == .relativeLoad
                         ? "Ready: \(set.isTestedMax ? "tested" : "estimated") 1RM \(Format.estimate(result.estimatedOneRepMaxKg ?? 0, unit: unit))"
                         : "Ready: \(Format.number(result.metric, maxFractionDigits: 1)) bodyweight reps")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                }
                .primeCard(padding: 12)
            case .failure(let reason):
                InlineError(message: reason.message).primeCard(padding: 12)
            }
        }
    }

    private var weightError: ValidationError? {
        guard !weightText.isEmpty, case .failure(let error) = InputValidator.weight(weightText, unit: unit) else { return nil }
        return error
    }
    private var repsError: ValidationError? {
        guard !repsText.isEmpty, case .failure(let error) = InputValidator.reps(repsText) else { return nil }
        return error
    }
    private var bodyweightError: ValidationError? {
        guard !bodyweightText.isEmpty, case .failure(let error) = InputValidator.bodyweight(bodyweightText, unit: unit) else { return nil }
        return error
    }

    private func rankableSet(for exercise: Exercise) -> RankableSet? {
        let weight: Double?
        if weightText.isEmpty {
            weight = exercise.rankingMethod == .repetitions ? 0 : nil
        } else {
            weight = try? InputValidator.weight(weightText, unit: unit).get()
        }
        guard let weight, let reps = try? InputValidator.reps(repsText).get() else { return nil }
        let bodyweight = try? InputValidator.bodyweight(bodyweightText, unit: unit).get()
        return RankableSet(weightKg: weight, reps: reps, date: Date(), bodyweightKg: bodyweight)
    }

    private var canSubmit: Bool {
        guard let exercise, let set = rankableSet(for: exercise) else { return false }
        if case .success = RankingEngine.evaluate(set, standard: exercise.rankingStandard, scale: scale) { return true }
        return false
    }

    private func note(for exercise: Exercise) -> String {
        let base = exercise.rankingNote.isEmpty ? "" : exercise.rankingNote + " "
        return base + "Each equipment variation has its own tiers, so machines are never compared with free weights. The result is saved to this lift's rank history."
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        unit = profiles.first?.weightUnit ?? .kg
        if let initialSlug { exercise = exercises.first { $0.slug == initialSlug } }
        if let bodyweight = store.history.latestBodyweightKg {
            bodyweightText = Format.number(unit.fromKilograms(bodyweight), maxFractionDigits: 1)
        }
    }

    private func convertInputs(from old: WeightUnit, to new: WeightUnit) {
        func convert(_ text: String) -> String {
            guard let value = InputValidator.parseNumber(text) else { return text }
            return Format.number(new.fromKilograms(old.toKilograms(value)), maxFractionDigits: 1)
        }
        weightText = convert(weightText)
        bodyweightText = convert(bodyweightText)
    }

    private func submit(_ exercise: Exercise) {
        focus = nil
        guard let set = rankableSet(for: exercise) else {
            failure = "Check the numbers you entered."
            Haptics.error()
            return
        }
        switch RankingService.submit(exercise: exercise, weightKg: set.weightKg, reps: set.reps, bodyweightKg: set.bodyweightKg,
                                     history: store.history, context: context, unit: unit, scale: scale) {
        case .failure(let reason):
            failure = reason.message
            Haptics.error()
        case .success(let reveal):
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { appState.reveal = reveal }
        }
    }
}

struct ThresholdEditorSheet: View {
    @Bindable var exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]
    @State private var texts = Array(repeating: "", count: RankTier.thresholdCount)
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(1...RankTier.thresholdCount, id: \.self) { index in
                        let tier = RankTier(rawValue: index) ?? .bronze
                        HStack {
                            RankEmblem(tier: tier, size: 28)
                            Text(tier.name)
                            Spacer()
                            TextField(placeholder(index - 1), text: $texts[index - 1])
                                .keyboardType(exercise.rankingMethod == .relativeLoad ? .decimalPad : .numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text(exercise.rankingMethod == .relativeLoad ? "× BW" : "reps").foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: { Text(exercise.rankingMethod.metricName) } footer: {
                    Text("Each tier starts at the value you enter, and each must be higher than the one before. Leave them all blank to use PRIME's tiers (shown in grey). Rank history from workouts is recalculated; performances you logged keep the rank they earned at the time.")
                }
                if let error { Section { InlineError(message: error) } }
                if exercise.customThresholds != nil && !exercise.defaultThresholds.isEmpty {
                    Section {
                        Button("Reset to PRIME's tiers", role: .destructive) {
                            exercise.customThresholds = nil
                            persist()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Customise tiers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let custom = exercise.customThresholds, custom.count == RankTier.thresholdCount { texts = custom.map { Format.number($0) } }
            }
        }
    }

    private func placeholder(_ index: Int) -> String {
        guard exercise.defaultThresholds.count == RankTier.thresholdCount else { return "" }
        return Format.number(exercise.defaultThresholds[index] * (profiles.first?.tierScale ?? 1))
    }

    private func save() {
        if texts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            if exercise.defaultThresholds.isEmpty {
                error = "This exercise has no default tiers, so enter all seven."
                return
            }
            exercise.customThresholds = nil
            persist()
            return
        }
        let values = texts.map { InputValidator.parseNumber($0) }
        guard values.allSatisfy({ $0 != nil }) else {
            error = "Enter a number for every tier."
            Haptics.error()
            return
        }
        let numbers = values.compactMap { $0 }
        guard RankingStandard.isValid(numbers) else {
            error = "Each tier must be higher than the one before it."
            Haptics.error()
            return
        }
        exercise.customThresholds = numbers
        persist()
    }

    private func persist() {
        try? context.save()
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profiles.first?.tierScale ?? 1)
        Haptics.success()
        dismiss()
    }
}
