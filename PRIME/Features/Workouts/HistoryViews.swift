import SwiftData
import SwiftUI

struct HistoryListView: View {
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        let sessions = store.history.sessions
        let calendar = Calendar.prime
        let groups = Dictionary(grouping: sessions) { calendar.startOfMonth(for: $0.startedAt) }
        let months = groups.keys.sorted(by: >)
        let recordCounts = Dictionary(grouping: records.compactMap(\.sessionID), by: { $0 }).mapValues(\.count)

        return VStack(alignment: .leading, spacing: 16) {
            if sessions.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "No workouts yet",
                               message: "Finished workouts are kept here forever, with every set you logged.")
            }
            ForEach(months, id: \.self) { month in
                let items = groups[month] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(month.formatted(.dateTime.month(.wide).year())).eyebrow()
                        Spacer()
                        Text("\(items.count) workout\(items.count == 1 ? "" : "s") · \(Format.volume(items.reduce(0) { $0 + $1.volume }, unit: unit))")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(items) { session in
                        NavigationLink(value: Route.session(session.id)) {
                            SessionRow(session: session, unit: unit, records: recordCounts[session.id] ?? 0)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let unit: WeightUnit
    let records: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(session.startedAt.formatted(.dateTime.day())).font(.primeNumber(24)).foregroundStyle(.white)
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.bold)).foregroundStyle(Theme.textSecondary).textCase(.uppercase)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(Format.duration(session.duration)) · \(session.setCount) sets · \(Format.volume(session.volume, unit: unit))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if records > 0 {
                Label("\(records)", systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityLabel("\(records) personal records")
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 12)
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var allRecords: [PersonalRecord]
    @State private var confirmDelete = false
    @State private var isEditing = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var records: [PersonalRecord] { allRecords.filter { $0.sessionID == session.uuid } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
                    .eyebrow()
                HStack(spacing: 10) {
                    StatTile(value: Format.duration(session.duration), label: "Duration", symbol: "clock.fill")
                    StatTile(value: Format.volume(session.totalVolume, unit: unit, includeUnit: false), label: "Volume (\(unit.symbol))", symbol: "scalemass.fill")
                    StatTile(value: "\(session.completedSets.count)", label: "Sets", symbol: "checkmark.circle.fill")
                }
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Records set")
                        ForEach(records) { RecordRow(record: $0, unit: unit) }
                    }
                    .primeCard(padding: 16)
                }
                if !session.notes.isEmpty {
                    Text(session.notes).font(.subheadline).foregroundStyle(Theme.textSecondary).primeCard()
                }
                ForEach(session.sortedExercises) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            NavigationLink(value: Route.exercise(item.exerciseSlug)) {
                                Text(item.exerciseName).font(.primeHeadline).foregroundStyle(.white)
                            }
                            Spacer()
                            if item.isSkipped { Tag(text: "Skipped", color: Theme.textTertiary) }
                        }
                        ForEach(Array(item.completedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                            HStack {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 20)
                                Text(Format.set(weightKg: set.weightKg, reps: set.reps, unit: unit))
                                    .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                                if set.isWarmup { Tag(text: "Warm-up", color: Theme.info) }
                                Spacer()
                                if let w = set.weightKg, let r = set.reps, let e1rm = StrengthMath.estimatedOneRepMax(weight: w, reps: r) {
                                    Text("e1RM " + Format.weight(e1rm, unit: unit)).font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .primeCard()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isEditing = true } label: { Label("Edit workout", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete workout", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Workout options")
            }
        }
        .sheet(isPresented: $isEditing) { SessionEditorView(session: session) }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    WorkoutService.deleteCompleted(session, context: context, store: store, profile: profiles.first, exercises: exercises)
                }
            }
        } message: {
            Text("Its sets, records and rank history will be removed. This can't be undone.")
        }
    }
}

/// Corrects a finished workout. Values are validated, then records and ranks are rebuilt.
struct SessionEditorView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    struct SetDraft: Identifiable {
        let id: PersistentIdentifier
        let set: ExerciseSet
        var weight: String
        var reps: String
        var delete = false
    }

    @State private var name = ""
    @State private var notes = ""
    @State private var drafts: [PersistentIdentifier: SetDraft] = [:]
    @State private var loaded = false
    @State private var errorText: String?

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            List {
                Section("Workout") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }
                ForEach(session.sortedExercises.filter { !$0.completedSets.isEmpty }) { item in
                    Section(item.exerciseName) {
                        ForEach(item.completedSets) { set in
                            if let draft = drafts[set.persistentModelID] {
                                editorRow(draft: draft, requiresLoad: item.equipment.requiresLoad)
                            }
                        }
                    }
                }
                if let errorText {
                    Section { InlineError(message: errorText) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
            .onAppear(perform: load)
        }
    }

    private func editorRow(draft: SetDraft, requiresLoad: Bool) -> some View {
        let binding = Binding<SetDraft>(get: { drafts[draft.id] ?? draft }, set: { drafts[draft.id] = $0 })
        return HStack(spacing: 10) {
            TextField("0", text: binding.weight)
                .keyboardType(.decimalPad)
                .frame(width: 70)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
            Text(unit.symbol).foregroundStyle(Theme.textSecondary)
            Text("×").foregroundStyle(Theme.textTertiary)
            TextField("0", text: binding.reps)
                .keyboardType(.numberPad)
                .frame(width: 50)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
            Text("reps").foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                binding.wrappedValue.delete.toggle()
            } label: {
                Image(systemName: binding.wrappedValue.delete ? "arrow.uturn.backward.circle.fill" : "trash")
                    .foregroundStyle(binding.wrappedValue.delete ? Theme.accent : Theme.danger)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(binding.wrappedValue.delete ? "Keep set" : "Delete set")
        }
        .opacity(binding.wrappedValue.delete ? 0.4 : 1)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = session.name
        notes = session.notes
        for item in session.exercises {
            for set in item.completedSets {
                drafts[set.persistentModelID] = SetDraft(
                    id: set.persistentModelID, set: set,
                    weight: set.weightKg.map { Format.number(unit.fromKilograms($0)) } ?? "",
                    reps: set.reps.map(String.init) ?? ""
                )
            }
        }
    }

    private func save() {
        // Validate everything before changing anything.
        var parsed: [PersistentIdentifier: (Double?, Int)] = [:]
        for item in session.exercises {
            for set in item.completedSets {
                guard let draft = drafts[set.persistentModelID], !draft.delete else { continue }
                let reps: Int
                switch InputValidator.reps(draft.reps) {
                case .success(let value): reps = value
                case .failure(let error):
                    errorText = "\(item.exerciseName): reps – \(error.errorDescription ?? "invalid")"
                    Haptics.error()
                    return
                }
                var weight: Double?
                if !draft.weight.trimmingCharacters(in: .whitespaces).isEmpty {
                    switch InputValidator.weight(draft.weight, unit: unit) {
                    case .success(let kg): weight = kg
                    case .failure(let error):
                        errorText = "\(item.exerciseName): weight – \(error.errorDescription ?? "invalid")"
                        Haptics.error()
                        return
                    }
                }
                if let problem = InputValidator.completedSetError(weightKg: weight, reps: reps, requiresLoad: item.equipment.requiresLoad) {
                    errorText = "\(item.exerciseName): \(problem.errorDescription ?? "invalid set")"
                    Haptics.error()
                    return
                }
                parsed[set.persistentModelID] = (weight, reps)
            }
        }
        guard !parsed.isEmpty else {
            errorText = "A workout needs at least one set. Delete the workout instead."
            Haptics.error()
            return
        }
        session.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? session.name : name
        session.notes = notes
        for item in session.exercises {
            for set in item.completedSets {
                if let values = parsed[set.persistentModelID] {
                    set.weightKg = values.0
                    set.reps = values.1
                } else {
                    context.delete(set)
                }
            }
        }
        try? context.save()
        for item in session.exercises where !item.sets.contains(where: \.isCompleted) { item.isSkipped = true }
        try? context.save()
        store.refresh(context)
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profiles.first?.tierScale ?? 1)
        Haptics.success()
        dismiss()
    }
}
