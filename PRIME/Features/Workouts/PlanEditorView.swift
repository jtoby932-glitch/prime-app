import SwiftData
import SwiftUI

/// Edits a copy of the routine so Cancel really cancels, and nothing invalid is saved.
struct PlanDraft {
    struct Entry: Identifiable {
        let id = UUID()
        var exercise: Exercise
        var sets: Int
        var reps: Int
        var weightText: String
        var rest: Int
    }

    var name = ""
    var notes = ""
    var colorIndex = 0
    var entries: [Entry] = []
    var weekdays: Set<Int> = []

    init() {}

    init(plan: WorkoutPlan, unit: WeightUnit) {
        name = plan.name
        notes = plan.notes
        colorIndex = plan.colorIndex
        weekdays = Set(plan.assignedWeekdays)
        entries = plan.sortedEntries.compactMap { entry in
            guard let exercise = entry.exercise else { return nil }
            return Entry(exercise: exercise, sets: entry.targetSets, reps: entry.targetReps,
                         weightText: entry.targetWeightKg.map { Format.number(unit.fromKilograms($0)) } ?? "",
                         rest: entry.restSeconds)
        }
    }

    func weightError(_ entry: Entry, unit: WeightUnit) -> String? {
        guard !entry.weightText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if case .failure(let error) = InputValidator.weight(entry.weightText, unit: unit) { return error.errorDescription }
        return nil
    }

    func problems(unit: WeightUnit) -> [String] {
        var problems: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Give the routine a name.") }
        if entries.isEmpty { problems.append("Add at least one exercise.") }
        if entries.contains(where: { weightError($0, unit: unit) != nil }) { problems.append("Fix the highlighted target weights.") }
        return problems
    }
}

struct PlanEditorView: View {
    let target: PlanEditorTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @State private var draft = PlanDraft()
    @State private var loaded = false
    @State private var showPicker = false
    @State private var showProblems = false
    @State private var editMode: EditMode = .inactive

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var defaultRest: Int { profiles.first?.defaultRestSeconds ?? 90 }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine name, e.g. Push Day", text: $draft.name)
                        .font(.headline)
                    HStack(spacing: 12) {
                        ForEach(0..<Theme.palette.count, id: \.self) { index in
                            Button {
                                draft.colorIndex = index
                            } label: {
                                Circle()
                                    .fill(Theme.planColor(index))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: draft.colorIndex == index ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour \(index + 1)")
                        }
                    }
                    .padding(.vertical, 6)
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: { Text("Routine") }

                Section {
                    HStack(spacing: 6) {
                        ForEach(Weekday.all, id: \.self) { index in
                            let selected = draft.weekdays.contains(index)
                            Button {
                                if selected { draft.weekdays.remove(index) } else { draft.weekdays.insert(index) }
                                Haptics.selection()
                            } label: {
                                Text(Weekday.initials[index])
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accent : Theme.field))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Weekday.longNames[index])
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Train it on") } footer: {
                    Text(conflictNote)
                }

                Section {
                    if draft.entries.isEmpty {
                        Text("No exercises yet.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach($draft.entries) { $entry in
                        PlanEntryRow(entry: $entry, unit: unit, error: draft.weightError(entry, unit: unit))
                    }
                    .onDelete { draft.entries.remove(atOffsets: $0) }
                    .onMove { draft.entries.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add exercises", systemImage: "plus.circle.fill").font(.headline)
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if draft.entries.count > 1 {
                            Button(editMode == .active ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode == .active ? .inactive : .active }
                            }
                            .font(.caption.weight(.bold))
                            .textCase(nil)
                        }
                    }
                }

                if showProblems, !draft.problems(unit: unit).isEmpty {
                    Section {
                        ForEach(draft.problems(unit: unit), id: \.self) { InlineError(message: $0) }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView(mode: .multiple, title: "Add exercises") { picked in
                    for exercise in picked {
                        draft.entries.append(.init(exercise: exercise, sets: 3, reps: exercise.rankingMethod == .repetitions ? 10 : (exercise.mechanic == .compound ? 8 : 12),
                                                   weightText: "", rest: exercise.mechanic == .compound ? max(defaultRest, 120) : defaultRest))
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var conflictNote: String {
        let taken = draft.weekdays.sorted().compactMap { weekday -> String? in
            guard let day = days.first(where: { $0.weekday == weekday }), let other = day.plan else { return nil }
            if case .edit(let plan) = target, plan.uuid == other.uuid { return nil }
            return "\(Weekday.shortNames[weekday]) (\(other.name))"
        }
        if taken.isEmpty { return "Leave empty to keep it unscheduled. You can start any routine at any time." }
        return "This will replace " + taken.joined(separator: ", ") + "."
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new(let weekday):
            draft.colorIndex = (try? context.fetchCount(FetchDescriptor<WorkoutPlan>())) ?? 0
            if let weekday { draft.weekdays = [weekday] }
        case .edit(let plan):
            draft = PlanDraft(plan: plan, unit: unit)
        }
    }

    private func save() {
        guard draft.problems(unit: unit).isEmpty else {
            withAnimation { showProblems = true }
            Haptics.error()
            return
        }
        let plan: WorkoutPlan
        switch target {
        case .new:
            plan = WorkoutPlan(name: draft.name.trimmingCharacters(in: .whitespaces), notes: draft.notes, colorIndex: draft.colorIndex)
            context.insert(plan)
        case .edit(let existing):
            plan = existing
            plan.name = draft.name.trimmingCharacters(in: .whitespaces)
            plan.notes = draft.notes
            plan.colorIndex = draft.colorIndex
            plan.updatedAt = Date()
            for entry in plan.entries { context.delete(entry) }
        }
        for (position, item) in draft.entries.enumerated() {
            var weight: Double?
            if case .success(let kg) = InputValidator.weight(item.weightText, unit: unit) { weight = kg > 0 ? kg : nil }
            let entry = PlannedExercise(position: position, exercise: item.exercise, targetSets: item.sets,
                                        targetReps: item.reps, targetWeightKg: weight, restSeconds: item.rest)
            context.insert(entry)
            entry.plan = plan
        }
        for day in ScheduleService.ensureWeek(context: context) {
            if draft.weekdays.contains(day.weekday) {
                day.plan = plan
                day.isRest = false
            } else if day.plan?.uuid == plan.uuid {
                day.plan = nil
            }
        }
        try? context.save()
        if let profile = profiles.first, !profile.hasCreatedFirstWorkout { profile.hasCreatedFirstWorkout = true }
        appState.refreshNotifications(context: context, history: store.history)
        Haptics.success()
        dismiss()
    }
}

struct PlanEntryRow: View {
    @Binding var entry: PlanDraft.Entry
    let unit: WeightUnit
    let error: String?

    private static let restOptions = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ExerciseIllustration(exercise: entry.exercise, size: 34)
                Text(entry.exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            HStack(spacing: 14) {
                MiniStepper(label: "Sets", value: $entry.sets, range: InputValidator.setRange)
                MiniStepper(label: "Reps", value: $entry.reps, range: 1...100)
            }
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("Target").font(.caption).foregroundStyle(Theme.textSecondary)
                    TextField(entry.exercise.equipment.requiresLoad ? "Any" : "+0", text: $entry.weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 64, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(error == nil ? .clear : Theme.danger, lineWidth: 1.5))
                    Text(unit.symbol).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Menu {
                    ForEach(Self.restOptions, id: \.self) { seconds in
                        Button(seconds == 0 ? "No rest timer" : Format.clock(TimeInterval(seconds))) { entry.rest = seconds }
                    }
                } label: {
                    Label(entry.rest == 0 ? "Off" : Format.clock(TimeInterval(entry.rest)), systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.field))
                }
                .accessibilityLabel("Rest time")
            }
            if let error { InlineError(message: error) }
        }
        .padding(.vertical, 6)
    }
}

struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 0) {
                button("minus") { value = max(range.lowerBound, value - 1) }
                Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit()).frame(minWidth: 28)
                button("plus") { value = min(range.upperBound, value + 1) }
            }
            .background(Capsule().fill(Theme.field))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Image(systemName: symbol).font(.caption.weight(.bold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
    }
}
