import SwiftData
import SwiftUI
import UIKit

struct ExerciseCard: View {
    @Bindable var item: ExerciseSession
    let session: WorkoutSession
    let unit: WeightUnit
    var focus: FocusState<SetField?>.Binding
    let onReplace: () -> Void
    let onNotes: () -> Void
    let onGuide: () -> Void
    let onRecord: ([RecordKind], ExerciseSession) -> Void

    private var timed: Bool { ExerciseLibrary.shared.isTimed(item.exerciseSlug) }

    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @State private var confirmRemove = false

    private static let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        let last = store.history.lastPerformance(for: item.exerciseSlug)
        VStack(alignment: .leading, spacing: 12) {
            header
            if item.isSkipped {
                HStack {
                    Label("Skipped", systemImage: "forward.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Unskip") { item.isSkipped = false; try? context.save() }
                        .font(.subheadline.weight(.bold))
                }
            } else {
                if !last.isEmpty, let date = last.first?.date {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last session · \(date.relativeDayText)").eyebrow(Theme.textTertiary)
                        Text(last.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed) }.joined(separator: "   "))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                if let target = item.targetReps {
                    Label("Target \(item.sets.count) × \(timed ? Format.hold(target) : "\(target)")" + (item.targetWeightKg.map { " @ \(Format.weight($0, unit: unit))" } ?? ""),
                          systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accentHighlight)
                }
                if !item.notes.isEmpty {
                    Button(action: onNotes) {
                        Label(item.notes, systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                columnHeaders
                ForEach(Array(item.sortedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                    SetRowView(
                        set: set, item: item, session: session, index: index,
                        previous: index < last.count ? last[index] : nil,
                        unit: unit, timed: timed, focus: focus, onRecord: { onRecord($0, item) }
                    )
                }
                HStack {
                    Button {
                        WorkoutService.addSet(to: item, context: context)
                        Haptics.tap()
                    } label: {
                        Label("Add set", systemImage: "plus").font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.prime(.secondary, compact: true))
                    Spacer()
                    Menu {
                        ForEach(Self.restOptions, id: \.self) { seconds in
                            Button(seconds == 0 ? "No rest timer" : Format.clock(TimeInterval(seconds))) {
                                item.restSeconds = seconds
                                try? context.save()
                            }
                        }
                    } label: {
                        Label(item.restSeconds == 0 ? "Off" : Format.clock(TimeInterval(item.restSeconds)), systemImage: "timer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.field))
                    }
                    .accessibilityLabel("Rest time for \(item.exerciseName)")
                }
            }
        }
        .primeCard(padding: 14)
        .opacity(item.isSkipped ? 0.6 : 1)
        .confirmationDialog("Remove \(item.exerciseName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                WorkoutService.remove(item, from: session, context: context)
            }
        } message: {
            Text("Its completed sets will be removed from this workout.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.exercise(item.exerciseSlug)) {
                HStack(spacing: 10) {
                    ExerciseIllustration(primary: item.primaryMuscles, secondary: [], equipment: item.equipment, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.exerciseName).font(.primeHeadline).foregroundStyle(.white).lineLimit(1)
                        Text(item.primaryMuscles.map(\.displayName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if item.exercise != nil {
                Button(action: onGuide) {
                    Image(systemName: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentHighlight)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.accentSoft))
                }
                .accessibilityLabel("Technique guide for \(item.exerciseName)")
            }
            Menu {
                Button(action: onGuide) { Label("Technique guide", systemImage: "book.pages") }
                    .disabled(item.exercise == nil)
                Button(action: onReplace) { Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath") }
                Button(action: onNotes) { Label(item.notes.isEmpty ? "Add note" : "Edit note", systemImage: "note.text") }
                Button {
                    item.isSkipped.toggle()
                    try? context.save()
                } label: { Label(item.isSkipped ? "Unskip exercise" : "Skip exercise", systemImage: "forward.fill") }
                Divider()
                Button { move(by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(isFirst)
                Button { move(by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(isLast)
                Divider()
                Button(role: .destructive) {
                    if item.completedSets.isEmpty {
                        WorkoutService.remove(item, from: session, context: context)
                    } else {
                        confirmRemove = true
                    }
                } label: { Label("Remove from workout", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.field))
            }
            .accessibilityLabel("Options for \(item.exerciseName)")
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            Text(item.equipment.requiresLoad && !timed ? unit.symbol.uppercased() : "+\(unit.symbol.uppercased())").frame(width: 74)
            Text(timed ? "SEC" : "REPS").frame(width: 58)
            Color.clear.frame(width: 40, height: 1)
        }
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }

    private var isFirst: Bool { session.sortedExercises.first?.persistentModelID == item.persistentModelID }
    private var isLast: Bool { session.sortedExercises.last?.persistentModelID == item.persistentModelID }

    private func move(by offset: Int) {
        let ordered = session.sortedExercises
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        withAnimation(.snappy) {
            WorkoutService.move(session, from: IndexSet(integer: index), to: offset > 0 ? target + 1 : target, context: context)
        }
    }
}

// MARK: - Set row

struct SetRowView: View {
    @Bindable var set: ExerciseSet
    let item: ExerciseSession
    let session: WorkoutSession
    let index: Int
    let previous: SetSample?
    let unit: WeightUnit
    var timed = false
    var focus: FocusState<SetField?>.Binding
    let onRecord: ([RecordKind]) -> Void

    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var loaded = false
    @State private var shakes = 0
    @State private var message: String?

    private var requiresLoad: Bool { item.equipment.requiresLoad && !timed }
    private var suggestion: SetSuggestion { WorkoutService.suggestion(for: set, in: item, history: store.history) }

    private var weightError: ValidationError? {
        guard !weightText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if case .failure(let error) = InputValidator.weight(weightText, unit: unit) { return error }
        return nil
    }

    private var repsError: ValidationError? {
        guard !repsText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if case .failure(let error) = InputValidator.count(repsText, timed: timed) { return error }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(set.isWarmup ? "W" : "\(index + 1)")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(set.isWarmup ? Theme.info : (set.isCompleted ? Theme.accent : Theme.textSecondary))
                    .frame(width: 30, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.field.opacity(set.isCompleted ? 0 : 1)))

                Button(action: copyPrevious) {
                    Text(previous.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed) } ?? "–")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(previous == nil || set.isCompleted ? Theme.textTertiary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(previous == nil || set.isCompleted)
                .accessibilityLabel(previous.map { "Copy last time: \(Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed))" } ?? "No previous set")

                field(text: $weightText, placeholder: weightPlaceholder, keyboard: .decimalPad,
                      field: .weight(set.persistentModelID), hasError: weightError != nil, width: 74)
                    .accessibilityLabel("Weight in \(unit.displayName), set \(index + 1)")
                field(text: $repsText, placeholder: suggestion.reps.map(String.init) ?? "0", keyboard: .numberPad,
                      field: .reps(set.persistentModelID), hasError: repsError != nil, width: 58)
                    .accessibilityLabel("Reps, set \(index + 1)")

                Button(action: toggle) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(set.isCompleted ? Theme.onAccent : Theme.textSecondary)
                        .frame(width: 40, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(set.isCompleted ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.field)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(set.isCompleted ? "Set \(index + 1) done. Tap to undo." : "Complete set \(index + 1)")
            }
            .modifier(Shake(animatableData: CGFloat(shakes)))
            if let message {
                InlineError(message: message).padding(.leading, 38)
            } else if let error = weightError ?? repsError {
                InlineError(message: error.errorDescription ?? "Invalid").padding(.leading, 38)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(set.isCompleted ? Theme.accent.opacity(0.08) : .clear))
        .animation(.easeOut(duration: 0.2), value: set.isCompleted)
        .contextMenu {
            if index > 0 {
                Button(action: copyAbove) { Label("Copy set above", systemImage: "doc.on.doc") }
            }
            Button {
                set.isWarmup.toggle()
                try? context.save()
            } label: { Label(set.isWarmup ? "Make working set" : "Mark as warm-up", systemImage: "flame") }
            Button(role: .destructive) {
                WorkoutService.removeSet(set, from: item, context: context)
            } label: { Label("Delete set", systemImage: "trash") }
        }
        .onAppear(perform: load)
        .onChange(of: weightText) { _, text in writeWeight(text) }
        .onChange(of: repsText) { _, text in writeReps(text) }
    }

    private var weightPlaceholder: String {
        if let weight = suggestion.weightKg, weight > 0 { return Format.number(unit.fromKilograms(weight)) }
        return requiresLoad ? "0" : "+0"
    }

    private func field(text: Binding<String>, placeholder: String, keyboard: UIKeyboardType, field: SetField, hasError: Bool, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused(focus, equals: field)
            .multilineTextAlignment(.center)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(set.isCompleted ? Theme.accent : .white)
            .frame(width: width, height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hasError ? Theme.danger : (focus.wrappedValue == field ? Theme.accent : .clear), lineWidth: 1.5)
            )
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let weight = set.weightKg, weight > 0 || requiresLoad {
            weightText = Format.number(unit.fromKilograms(weight))
        }
        if let reps = set.reps { repsText = String(reps) }
    }

    private func writeWeight(_ text: String) {
        message = nil
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            set.weightKg = nil
        } else if case .success(let kilograms) = InputValidator.weight(text, unit: unit) {
            set.weightKg = kilograms
        }
    }

    private func writeReps(_ text: String) {
        message = nil
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            set.reps = nil
        } else if case .success(let reps) = InputValidator.count(text, timed: timed) {
            set.reps = reps
        }
    }

    /// Fills this set with the values of the set above it.
    private func copyAbove() {
        let ordered = item.sortedSets
        guard index > 0, index - 1 < ordered.count else { return }
        let above = ordered[index - 1]
        if let weight = above.weightKg { weightText = Format.number(unit.fromKilograms(weight)) }
        if let reps = above.reps { repsText = String(reps) }
        Haptics.selection()
    }

    /// Tapping last session's numbers copies them into this set.
    private func copyPrevious() {
        guard let previous else { return }
        if previous.weightKg > 0 || requiresLoad { weightText = Format.number(unit.fromKilograms(previous.weightKg)) }
        repsText = String(previous.reps)
        Haptics.selection()
    }

    private func toggle() {
        if set.isCompleted {
            WorkoutService.uncomplete(set, context: context)
            Haptics.tap()
            return
        }
        if weightError != nil || repsError != nil {
            reject(nil)
            return
        }
        // Ticking an empty row accepts the suggested values shown in grey.
        if weightText.trimmingCharacters(in: .whitespaces).isEmpty, let weight = suggestion.weightKg, weight > 0 {
            set.weightKg = weight
            weightText = Format.number(unit.fromKilograms(weight))
        }
        if repsText.trimmingCharacters(in: .whitespaces).isEmpty, let reps = suggestion.reps {
            set.reps = reps
            repsText = String(reps)
        }
        do {
            let records = try WorkoutService.complete(set, in: item, session: session, history: store.history, context: context)
            focus.wrappedValue = nil
            Haptics.thud()
            let profile = profiles.first
            if item.restSeconds > 0 {
                WorkoutService.startRest(session, seconds: item.restSeconds, label: item.exerciseName, notify: profile?.notifyRestTimer ?? true)
                try? context.save()
            }
            if !records.isEmpty { onRecord(records) }
        } catch {
            reject(error.localizedDescription)
        }
    }

    private func reject(_ text: String?) {
        Haptics.error()
        message = text
        withAnimation(.default) { shakes += 1 }
    }
}

/// Horizontal shake for rejected input.
struct Shake: GeometryEffect {
    var amount: CGFloat = 6
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}
