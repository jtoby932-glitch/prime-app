import SwiftData
import SwiftUI

/// Guides a new user to their first routines: a starter split laid over their days, or their own.
struct FirstWorkoutGuide: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var selected: PlanTemplate.ID?
    @State private var weekdays: Set<Int> = []
    @State private var created: [WorkoutPlan] = []
    @State private var showEditor = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if created.isEmpty {
                        chooser
                    } else {
                        success
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .primeBackground()
            .navigationTitle(created.isEmpty ? "Your first week" : "Plan ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(created.isEmpty ? "Not now" : "Close") { dismiss() } }
            }
            .sheet(isPresented: $showEditor) { PlanEditorView(target: .new(weekday: weekdays.sorted().first)) }
            .onAppear {
                if weekdays.isEmpty {
                    weekdays = Set(profile?.preferredWeekdays ?? [])
                    if weekdays.isEmpty { weekdays = [0, 2, 4] }
                }
                if selected == nil {
                    selected = PlanTemplate.recommended(forDays: weekdays.count, experience: profile?.experience ?? .beginner)
                }
            }
        }
    }

    private var chooser: some View {
        let recommended = PlanTemplate.recommended(forDays: weekdays.count, experience: profile?.experience ?? .beginner)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Pick a starting split. It becomes ordinary routines you can edit, rename or delete.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Training days").eyebrow()
                HStack(spacing: 6) {
                    ForEach(Weekday.all, id: \.self) { day in
                        let on = weekdays.contains(day)
                        Button {
                            if on { weekdays.remove(day) } else { weekdays.insert(day) }
                            Haptics.selection()
                        } label: {
                            Text(Weekday.initials[day])
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(on ? Theme.onAccent : .white)
                                .background(RoundedRectangle(cornerRadius: 12).fill(on ? Theme.accent : Theme.card))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Weekday.longNames[day])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            ForEach(PlanTemplate.all) { template in
                let isSelected = selected == template.id
                Button {
                    selected = template.id
                    Haptics.selection()
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBubble(symbol: template.symbol, size: 38)
                            Text(template.name).font(.primeHeadline).foregroundStyle(.white)
                            if template.id == recommended { Tag(text: "Suggested", color: Theme.accent) }
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                        }
                        Text(template.summary).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                        ForEach(template.days, id: \.name) { day in
                            Text("\(day.name): " + day.items.compactMap { item in exercises.first { $0.slug == item.slug }?.name }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 1))
                }
                .buttonStyle(PressableStyle())
            }

            Button("Create my plan") { install() }
                .buttonStyle(.primePrimary)
                .disabled(selected == nil)
            Button("Build my own routine instead") { showEditor = true }
                .buttonStyle(.primeSecondary)
            if weekdays.isEmpty {
                Text("No days chosen, so the routines won't be scheduled. You can assign them in Workouts.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var success: some View {
        let todayIndex = Weekday.index(of: Date())
        let todayPlan = (try? context.fetch(FetchDescriptor<WorkoutDay>()))?.first { $0.weekday == todayIndex }?.plan
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBubble(symbol: "checkmark", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(created.count) routine\(created.count == 1 ? "" : "s") created").font(.primeHeadline).foregroundStyle(.white)
                    Text("Scheduled on " + (weekdays.isEmpty ? "no days yet" : weekdays.sorted().map { Weekday.shortNames[$0] }.joined(separator: ", ")))
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(created) { plan in
                RoutineCard(plan: plan)
            }
            if let todayPlan {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        appState.startWorkout(plan: todayPlan, context: context, store: store)
                    }
                } label: { Label("Start today's \(todayPlan.name)", systemImage: "play.fill") }
                    .buttonStyle(.primePrimary)
            }
            Button("Done") { dismiss() }.buttonStyle(.primeSecondary)
            Text("Tip: open a routine to change exercises, sets, target weights and rest times.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func install() {
        guard let id = selected, let template = PlanTemplate.all.first(where: { $0.id == id }) else { return }
        created = template.install(context: context, exercises: exercises, weekdays: Array(weekdays), restSeconds: profile?.defaultRestSeconds ?? 90)
        if let profile {
            profile.hasCreatedFirstWorkout = true
            if !weekdays.isEmpty {
                profile.preferredWeekdays = weekdays.sorted()
                profile.weeklyGoal = weekdays.count
            }
        }
        try? context.save()
        appState.refreshNotifications(context: context, history: store.history)
        Haptics.success()
    }
}
