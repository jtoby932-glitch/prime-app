import SwiftData
import SwiftUI

struct PlanDetailView: View {
    let plan: WorkoutPlan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @State private var editing: PlanEditorTarget?
    @State private var confirmDelete = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 12, height: 12)
                        Text(plan.assignedWeekdays.isEmpty ? "Not scheduled" : plan.assignedWeekdays.map { Weekday.longNames[$0] }.joined(separator: ", "))
                            .eyebrow()
                    }
                    if !plan.notes.isEmpty {
                        Text(plan.notes).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 10) {
                        StatTile(value: "\(plan.entries.count)", label: "Exercises")
                        StatTile(value: "\(plan.totalSets)", label: "Sets")
                        StatTile(value: "~\(plan.estimatedMinutes)", label: "Minutes")
                    }
                    Button {
                        appState.startWorkout(plan: plan, context: context, store: store)
                    } label: { Label("Start workout", systemImage: "play.fill") }
                        .buttonStyle(.primePrimary)
                }

                SectionHeader(title: "Exercises")
                VStack(spacing: 8) {
                    ForEach(plan.sortedEntries) { entry in
                        if let exercise = entry.exercise {
                            NavigationLink(value: Route.exercise(exercise.slug)) {
                                PlannedEntryCard(entry: entry, exercise: exercise, unit: unit,
                                                 last: store.history.lastPerformance(for: exercise.slug))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }

                if !plan.muscles.isEmpty {
                    SectionHeader(title: "Muscles worked")
                    HStack(spacing: 16) {
                        BodyModelReader { model in
                            AnatomyCanvas(side: .front, primary: plan.muscles, model: model).frame(height: 230)
                            AnatomyCanvas(side: .back, primary: plan.muscles, model: model).frame(height: 230)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .primeCard()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = .edit(plan) } label: { Label("Edit", systemImage: "pencil") }
                    Button { ScheduleService.duplicate(plan, context: context) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Routine options")
            }
        }
        .sheet(item: $editing) { PlanEditorView(target: $0) }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete routine", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    ScheduleService.delete(plan, context: context)
                    appState.refreshNotifications(context: context, history: store.history)
                }
            }
        } message: {
            Text("Logged workouts stay in your history.")
        }
    }
}

struct PlannedEntryCard: View {
    let entry: PlannedExercise
    let exercise: Exercise
    let unit: WeightUnit
    let last: [SetSample]

    var body: some View {
        HStack(spacing: 12) {
            ExerciseIllustration(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(targetText).font(.caption).foregroundStyle(Theme.textSecondary)
                if !last.isEmpty {
                    Text("Last: " + last.prefix(3).map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: $0.isTimed) }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 12)
    }

    private var targetText: String {
        var parts = ["\(entry.targetSets) × \(entry.targetReps)"]
        if let weight = entry.targetWeightKg { parts.append("@ " + Format.weight(weight, unit: unit)) }
        if entry.restSeconds > 0 { parts.append("rest " + Format.clock(TimeInterval(entry.restSeconds))) }
        return parts.joined(separator: "  ")
    }
}
