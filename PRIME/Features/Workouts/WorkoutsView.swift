import SwiftData
import SwiftUI

struct WorkoutsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case week = "Week", routines = "Routines", history = "History"
        var id: String { rawValue }
    }

    @State private var section: Segment = .week
    @State private var editorTarget: PlanEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Section", selection: $section) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .week: WeekPlannerView(editorTarget: $editorTarget)
                    case .routines: RoutinesListView(editorTarget: $editorTarget)
                    case .history: HistoryListView()
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .primeBackground()
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new(weekday: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New routine")
                }
            }
            .sheet(item: $editorTarget) { target in
                PlanEditorView(target: target)
            }
            .primeDestinations()
        }
    }
}

enum PlanEditorTarget: Identifiable {
    case new(weekday: Int?)
    case edit(WorkoutPlan)

    var id: String {
        switch self {
        case .new(let weekday): return "new-\(weekday ?? -1)"
        case .edit(let plan): return plan.uuid.uuidString
        }
    }
}

// MARK: - Week planner

struct WeekPlannerView: View {
    @Binding var editorTarget: PlanEditorTarget?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @State private var selectedWeekday = Weekday.index(of: Date())
    @State private var dayToEdit: WorkoutDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PresetBanner().appear(0)
            calendarStrip.appear(1)
            if let day = days.first(where: { $0.weekday == selectedWeekday }) {
                SelectedDayCard(day: day, editorTarget: $editorTarget, onEdit: { dayToEdit = day })
                    .appear(2)
            }
            SectionHeader(title: "Your week").appear(3)
            VStack(spacing: 8) {
                ForEach(days) { day in
                    Button {
                        withAnimation(.snappy) { selectedWeekday = day.weekday }
                        dayToEdit = day
                    } label: {
                        DayRow(day: day, isToday: day.weekday == Weekday.index(of: Date()))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text("Tap a day to assign a routine, make it a rest day or move it.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .sheet(item: $dayToEdit) { day in
            DayEditorSheet(day: day, editorTarget: $editorTarget)
                .presentationDetents([.medium, .large])
        }
    }

    private var calendarStrip: some View {
        let calendar = Calendar.prime
        let weekStart = calendar.startOfWeek(for: Date())
        let trained = Analytics.trainedDays(store.history.sessions)
        return HStack(spacing: 6) {
            ForEach(Weekday.all, id: \.self) { index in
                let date = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
                let day = days.first { $0.weekday == index }
                let isSelected = selectedWeekday == index
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { selectedWeekday = index }
                } label: {
                    VStack(spacing: 6) {
                        Text(Weekday.initials[index]).font(.caption2.weight(.bold))
                        Text(date.formatted(.dateTime.day())).font(.system(.headline, design: .default, weight: .bold)).monospacedDigit()
                        Circle()
                            .fill(trained.contains(calendar.startOfDay(for: date)) ? Theme.accent :
                                    day?.state == .training ? (day?.plan.map { Theme.planColor($0.colorIndex) } ?? Theme.accent).opacity(0.6) : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isSelected ? Theme.onAccent : (index == Weekday.index(of: Date()) ? Theme.accent : Theme.textPrimary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Weekday.longNames[index])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct SelectedDayCard: View {
    let day: WorkoutDay
    @Binding var editorTarget: PlanEditorTarget?
    var onEdit: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Weekday.longNames[day.weekday]).eyebrow()
            switch day.state {
            case .training:
                if let plan = day.plan {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 10, height: 10)
                            Text(plan.name).font(.primeTitle).foregroundStyle(.white)
                            Spacer()
                            Button("Change", action: onEdit).font(.subheadline.weight(.semibold))
                        }
                        ForEach(plan.sortedEntries.prefix(6)) { entry in
                            HStack {
                                Text(entry.exercise?.name ?? entry.exerciseName).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(entry.targetSets) × \(entry.targetReps)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                            }
                        }
                        if plan.entries.count > 6 {
                            Text("+ \(plan.entries.count - 6) more").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        HStack(spacing: 10) {
                            Button {
                                appState.startWorkout(plan: plan, context: context, store: store)
                            } label: { Label("Start", systemImage: "play.fill") }
                                .buttonStyle(.primePrimary)
                            Button("Edit routine") { editorTarget = .edit(plan) }
                                .buttonStyle(.primeSecondary)
                        }
                    }
                }
            case .rest:
                HStack(spacing: 12) {
                    IconBubble(symbol: "moon.zzz.fill", tint: Theme.info, size: 42)
                    VStack(alignment: .leading) {
                        Text("Rest day").font(.primeTitle).foregroundStyle(.white)
                        Text("Let your muscles recover and adapt.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Change", action: onEdit).font(.subheadline.weight(.semibold))
                }
            case .unplanned:
                Text("Nothing planned").font(.primeTitle).foregroundStyle(.white)
                HStack(spacing: 10) {
                    Button("Assign routine", action: onEdit).buttonStyle(.primePrimary)
                    Button("New routine") { editorTarget = .new(weekday: day.weekday) }.buttonStyle(.primeSecondary)
                }
            }
        }
        .primeHero(tint: day.plan.map { Theme.planColor($0.colorIndex) } ?? (day.state == .rest ? Theme.textSecondary : Theme.accent))
    }
}

struct DayRow: View {
    let day: WorkoutDay
    let isToday: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(Weekday.shortNames[day.weekday]).font(.subheadline.weight(.bold))
                    .foregroundStyle(isToday ? Theme.accent : Theme.textPrimary)
                if isToday { Circle().fill(Theme.accent).frame(width: 4, height: 4) }
            }
            .frame(width: 40)
            switch day.state {
            case .training:
                RoundedRectangle(cornerRadius: 2).fill(Theme.planColor(day.plan?.colorIndex ?? 0)).frame(width: 4, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.plan?.name ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("\(day.plan?.entries.count ?? 0) exercises · ~\(day.plan?.estimatedMinutes ?? 0) min").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            case .rest:
                RoundedRectangle(cornerRadius: 2).fill(Theme.textTertiary).frame(width: 4, height: 32)
                Text("Rest").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            case .unplanned:
                RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [3])).frame(width: 4, height: 32)
                Text("Unplanned").font(.subheadline).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day editor

struct DayEditorSheet: View {
    @Bindable var day: WorkoutDay
    @Binding var editorTarget: PlanEditorTarget?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]

    var body: some View {
        NavigationStack {
            List {
                if let plan = day.plan {
                    Section {
                        Button {
                            dismiss()
                            appState.startWorkout(plan: plan, context: context, store: store)
                        } label: { Label("Start \(plan.name) now", systemImage: "play.fill") }
                        Menu {
                            ForEach(days.filter { $0.weekday != day.weekday }) { other in
                                Button {
                                    ScheduleService.move(from: day, to: other, context: context)
                                    refresh()
                                    dismiss()
                                } label: {
                                    Text(Weekday.longNames[other.weekday] + (other.plan.map { " (swap with \($0.name))" } ?? (other.isRest ? " (swap with rest)" : "")))
                                }
                            }
                        } label: { Label("Move to another day", systemImage: "arrow.left.arrow.right") }
                    }
                }
                Section("Assign a routine") {
                    if plans.isEmpty {
                        Text("You haven't made any routines yet.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(plans) { plan in
                        Button {
                            ScheduleService.assign(plan, to: day, context: context)
                            Haptics.selection()
                            refresh()
                        } label: {
                            HStack {
                                Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 10, height: 10)
                                Text(plan.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if day.plan?.uuid == plan.uuid { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                    Button {
                        let weekday = day.weekday
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editorTarget = .new(weekday: weekday) }
                    } label: { Label("Create a new routine", systemImage: "plus") }
                }
                Section {
                    Button {
                        ScheduleService.setRest(day, context: context)
                        Haptics.selection()
                        refresh()
                    } label: {
                        HStack {
                            Label("Rest day", systemImage: "moon.zzz.fill")
                            Spacer()
                            if day.isRest { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                    if day.state != .unplanned {
                        Button(role: .destructive) {
                            ScheduleService.clear(day, context: context)
                            refresh()
                        } label: { Label("Clear this day", systemImage: "xmark.circle") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(Weekday.longNames[day.weekday])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func refresh() {
        appState.refreshNotifications(context: context, history: store.history)
    }
}

// MARK: - Routines

struct RoutinesListView: View {
    @Binding var editorTarget: PlanEditorTarget?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @State private var planToDelete: WorkoutPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if plans.isEmpty {
                EmptyStateView(symbol: "list.bullet.rectangle.portrait", title: "No routines yet",
                               message: "A routine is a list of exercises with your target sets, reps and weights.",
                               actionTitle: "Create routine") { editorTarget = .new(weekday: nil) }
                Button("Use a split preset") { appState.showSplitPresets = true }
                    .buttonStyle(.primeSecondary)
            }
            ForEach(plans) { plan in
                NavigationLink(value: Route.plan(plan.uuid)) {
                    RoutineCard(plan: plan)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button { appState.startWorkout(plan: plan, context: context, store: store) } label: { Label("Start", systemImage: "play.fill") }
                    Button { editorTarget = .edit(plan) } label: { Label("Edit", systemImage: "pencil") }
                    Button { ScheduleService.duplicate(plan, context: context) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Menu {
                        ForEach(days) { day in
                            Button(Weekday.longNames[day.weekday]) {
                                ScheduleService.assign(plan, to: day, context: context)
                                appState.refreshNotifications(context: context, history: store.history)
                            }
                        }
                    } label: { Label("Assign to day", systemImage: "calendar") }
                    Button(role: .destructive) { planToDelete = plan } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete routine", role: .destructive) {
                if let plan = planToDelete {
                    ScheduleService.delete(plan, context: context)
                    appState.refreshNotifications(context: context, history: store.history)
                }
                planToDelete = nil
            }
        } message: {
            Text("It will be removed from your timetable. Workouts you've already logged are kept.")
        }
    }
}

struct RoutineCard: View {
    let plan: WorkoutPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 10, height: 10)
                Text(plan.name).font(.primeHeadline).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
            Text(plan.sortedEntries.map { $0.exercise?.name ?? $0.exerciseName }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Tag(text: "\(plan.entries.count) exercises")
                Tag(text: "~\(plan.estimatedMinutes) min")
                ForEach(plan.assignedWeekdays, id: \.self) { Tag(text: Weekday.shortNames[$0], color: Theme.accent) }
            }
        }
        .primeCard()
    }
}


/// Entry point to the split preset library from the timetable.
struct PresetBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button { appState.showSplitPresets = true } label: {
            HStack(spacing: 12) {
                IconBubble(symbol: "square.stack.3d.up.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout split presets").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("PPL, Arnold, Upper/Lower and more, from any start day").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
            .primeCard(padding: 12)
        }
        .buttonStyle(PressableStyle())
    }
}
