import SwiftData
import SwiftUI
import UIKit

/// Rank any lift without logging it: exercise (which fixes the equipment variation), weight, reps and bodyweight.
struct RankCalculatorView: View {
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @State private var exercise: Exercise?
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var bodyweightText = ""
    @State private var showPicker = false
    @State private var loaded = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var scale: Double { profiles.first?.tierScale ?? 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { showPicker = true } label: {
                    HStack(spacing: 12) {
                        if let exercise {
                            ExerciseIllustration(exercise: exercise, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.headline).foregroundStyle(.white)
                                Text("\(exercise.equipment.displayName) · \(exercise.rankingMethod.metricName)").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        } else {
                            IconBubble(symbol: "dumbbell.fill", size: 44)
                            Text("Choose an exercise").font(.headline).foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").foregroundStyle(Theme.textTertiary)
                    }
                    .primeCard()
                }
                .buttonStyle(PressableStyle())

                if let exercise, exercise.isRanked {
                    VStack(spacing: 12) {
                        inputRow(title: exercise.equipment.requiresLoad ? "Weight" : "Added weight", text: $weightText,
                                 suffix: unit.symbol, keyboard: .decimalPad, error: weightError)
                        inputRow(title: "Reps", text: $repsText, suffix: "reps", keyboard: .numberPad, error: repsError)
                        inputRow(title: "Bodyweight", text: $bodyweightText, suffix: unit.symbol, keyboard: .decimalPad, error: bodyweightError)
                    }
                    .primeCard()
                    if !exercise.rankingNote.isEmpty {
                        Text(exercise.rankingNote).font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    resultCard(for: exercise)
                } else if let exercise {
                    Text("\(exercise.name) isn't ranked. \(exercise.rankingNote)").font(.subheadline).foregroundStyle(Theme.textSecondary).primeCard()
                }

                Text("Each equipment variation has its own tiers, so a dumbbell press is never compared with a barbell or machine press.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .primeBackground()
        .navigationTitle("Rank calculator")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(mode: .single, title: "Choose exercise") { exercise = $0.first }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let bodyweight = store.history.latestBodyweightKg { bodyweightText = Format.number(unit.fromKilograms(bodyweight), maxFractionDigits: 1) }
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

    private func inputRow(title: String, text: Binding<String>, suffix: String, keyboard: UIKeyboardType, error: ValidationError?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("0", text: text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .frame(width: 110)
                Text(suffix).font(.subheadline).foregroundStyle(Theme.textSecondary).frame(width: 34, alignment: .leading)
            }
            if let error { InlineError(message: error.errorDescription ?? "Invalid") }
        }
    }

    @ViewBuilder
    private func resultCard(for exercise: Exercise) -> some View {
        let weight: Double? = weightText.isEmpty ? (exercise.equipment.requiresLoad ? nil : 0) : (try? InputValidator.weight(weightText, unit: unit).get())
        let reps = try? InputValidator.reps(repsText).get()
        let bodyweight = try? InputValidator.bodyweight(bodyweightText, unit: unit).get()
        if let weight, let reps {
            let set = RankableSet(weightKg: weight, reps: reps, date: Date(), bodyweightKg: bodyweight)
            switch RankingEngine.evaluate(set, standard: exercise.rankingStandard, scale: scale) {
            case .success(let result):
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        TierBadgeView(tier: result.placement.tier, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.placement.tier.name).font(.primeLargeTitle).foregroundStyle(result.placement.tier.color)
                            Text(RankFormat.metric(result.metric, method: result.method)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        }
                    }
                    if result.placement.tier.next != nil {
                        ProgressBar(progress: result.placement.progress, tint: AnyShapeStyle(result.placement.tier.gradient), height: 8)
                    }
                    ForEach(Array(RankFormat.explanation(result, unit: unit, scale: scale, note: "").enumerated()), id: \.offset) { _, line in
                        Text(line).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .primeCard(padding: 18)
                TierLadder(method: exercise.rankingMethod, thresholds: exercise.rankingStandard.effectiveThresholds(scale: scale),
                           current: result, bodyweightKg: bodyweight, unit: unit)
            case .failure(let failure):
                InlineError(message: failure.message).primeCard()
            }
        } else {
            Text("Enter a valid \(exercise.equipment.requiresLoad ? "weight and " : "")rep count to see the rank.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
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
    @State private var texts = ["", "", "", ""]
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(1..<5, id: \.self) { index in
                        let tier = RankTier(rawValue: index) ?? .bronze
                        HStack {
                            TierBadgeView(tier: tier, size: 22)
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
                    Text("Each tier starts at the value you enter. Leave all blank and save to use the provisional defaults (shown in grey).")
                }
                if let error { Section { InlineError(message: error) } }
                if exercise.customThresholds != nil && !exercise.defaultThresholds.isEmpty {
                    Section {
                        Button("Reset to provisional tiers", role: .destructive) {
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
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let custom = exercise.customThresholds { texts = custom.map { Format.number($0) } }
            }
        }
    }

    private func placeholder(_ index: Int) -> String {
        guard exercise.defaultThresholds.count == 4 else { return "" }
        return Format.number(exercise.defaultThresholds[index] * (profiles.first?.tierScale ?? 1))
    }

    private func save() {
        if texts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            if exercise.defaultThresholds.isEmpty {
                error = "This exercise has no default tiers, so enter all four."
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

    /// Saves, then rebuilds rank history so the charts reflect the new tiers.
    private func persist() {
        try? context.save()
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profiles.first?.tierScale ?? 1)
        Haptics.success()
        dismiss()
    }
}
