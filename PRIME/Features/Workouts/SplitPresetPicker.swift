import SwiftData
import SwiftUI

/// Choose an established split, pick the day it starts on, preview the week, then apply.
struct SplitPresetPicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.motion) private var motion
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]

    @State private var selectedID: String?
    @State private var start = 0
    @State private var mode: PresetApplyMode = .replace
    @State private var confirming = false
    @State private var loaded = false
    @State private var applied: [WorkoutPlan]?

    private var profile: UserProfile? { profiles.first }
    private var preset: SplitPreset? { selectedID.flatMap(SplitPreset.find) }
    private var hasSchedule: Bool { days.contains { $0.state != .unplanned } }
    private var bySlug: [String: Exercise] { Dictionary(exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let applied {
                        success(applied)
                    } else {
                        presetList
                        if let preset {
                            startDayPicker
                            WeekPreviewCard(preset: preset, preview: ScheduleService.preview(preset, start: start, mode: hasSchedule ? mode : .replace, days: days, exercises: bySlug))
                                .id(preset.id + "\(start)\(mode.rawValue)")
                                .transition(.opacity)
                            if hasSchedule { modePicker }
                            Button {
                                if hasSchedule { confirming = true } else { apply() }
                            } label: {
                                Label("Apply \(preset.name)", systemImage: "checkmark")
                            }
                            .buttonStyle(.primePrimary)
                            Text("This creates your own copies of the workouts. Rename them, swap exercises, move days or add rest days whenever you like; the preset itself never changes.")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
                .animation(motion.animation(), value: selectedID)
                .animation(motion.animation(), value: start)
            }
            .primeBackground()
            .navigationTitle(applied == nil ? "Workout split presets" : "Timetable ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(applied == nil ? "Cancel" : "Close") { dismiss() } }
            }
            .confirmationDialog("Apply \(preset?.name ?? "preset")?", isPresented: $confirming, titleVisibility: .visible) {
                Button(mode == .replace ? "Replace my timetable" : "Fill empty days only") { apply() }
            } message: {
                Text(mode == .replace
                     ? "Every day will follow the preset. Your existing routines and workout history are kept; routines no longer on a day stay in Routines."
                     : "Only days with nothing planned will change. Nothing you've already scheduled is touched.")
            }
            .onAppear(perform: load)
        }
    }

    private var presetList: some View {
        let recommended = SplitPreset.recommended(forDays: max(profile?.preferredWeekdays.count ?? 0, profile?.weeklyGoal ?? 3),
                                                  experience: profile?.experience ?? .beginner)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Choose a split").eyebrow()
            ForEach(SplitPreset.all) { item in
                let selected = item.id == selectedID
                Button {
                    Haptics.selection()
                    selectedID = item.id
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        IconBubble(symbol: item.symbol, tint: selected ? Theme.accentHighlight : Theme.textSecondary, size: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                if item.id == recommended { Tag(text: "Suggested", color: Theme.accentHighlight) }
                            }
                            Text(item.summary).font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                            PresetStrip(preset: item, start: selected ? start : 0)
                        }
                        Spacer(minLength: 0)
                        Text("\(item.sessionsPerWeek)×").font(.primeNumber(18)).foregroundStyle(selected ? Theme.accentHighlight : Theme.textTertiary)
                            .accessibilityLabel("\(item.sessionsPerWeek) sessions a week")
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button {
                dismiss()
                appState.selectedTab = .workouts
            } label: {
                Label("Custom split: build my own", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primeSecondary)
        }
    }

    private var startDayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start the split on").eyebrow()
            HStack(spacing: 6) {
                ForEach(Weekday.all, id: \.self) { index in
                    let selected = start == index
                    Button {
                        Haptics.selection()
                        start = index
                    } label: {
                        Text(Weekday.shortNames[index])
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? .clear : Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Weekday.longNames[index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You already have a timetable").eyebrow()
            Picker("Apply mode", selection: $mode) {
                Text("Replace timetable").tag(PresetApplyMode.replace)
                Text("Fill empty days").tag(PresetApplyMode.fillEmpty)
            }
            .pickerStyle(.segmented)
        }
    }

    private func success(_ plans: [WorkoutPlan]) -> some View {
        let todayIndex = Weekday.index(of: Date())
        let todayPlan = days.first { $0.weekday == todayIndex }?.plan
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBubble(symbol: "checkmark", tint: Theme.success, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset?.name ?? "Split applied").font(.primeHeadline).foregroundStyle(Theme.textPrimary)
                    Text(plans.isEmpty ? "Reused your existing routines from this preset." : "\(plans.count) new routine\(plans.count == 1 ? "" : "s") created")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(spacing: 8) {
                ForEach(days) { DayRow(day: $0, isToday: $0.weekday == todayIndex) }
            }
            if let todayPlan {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { appState.startWorkout(plan: todayPlan, context: context, store: store) }
                } label: { Label("Start today's \(todayPlan.name)", systemImage: "play.fill") }
                    .buttonStyle(.primePrimary)
            }
            Button("Done") { dismiss() }.buttonStyle(.primeSecondary)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let preferred = profile?.preferredWeekdays ?? []
        start = SplitPreset.suggestedStart(preferred: preferred)
        if !hasSchedule { mode = .replace } else { mode = .fillEmpty }
    }

    private func apply() {
        guard let preset else { return }
        let created = ScheduleService.apply(preset, start: start, mode: hasSchedule ? mode : .replace, exercises: exercises,
                                            restSeconds: profile?.defaultRestSeconds ?? 90, context: context)
        if let profile { profile.hasCreatedFirstWorkout = true }
        try? context.save()
        appState.refreshNotifications(context: context, history: store.history)
        Haptics.success()
        withAnimation(motion.animation()) { applied = created }
    }
}

/// Seven tiny blocks showing sessions and rest days for a preset.
struct PresetStrip: View {
    let preset: SplitPreset
    var start: Int = 0

    var body: some View {
        let layout = preset.layout(startingOn: start)
        HStack(spacing: 3) {
            ForEach(Weekday.all, id: \.self) { day in
                let slot = layout[day] ?? nil
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(slot == nil ? AnyShapeStyle(Theme.field) : AnyShapeStyle(Theme.accent.opacity(0.85)))
                        .frame(height: 6)
                    Text(Weekday.initials[day]).font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
}

/// The full week the preset would produce.
struct WeekPreviewCard: View {
    let preset: SplitPreset
    let preview: [PresetPreviewDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your week").font(.primeTitle3).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(preview.filter { !$0.isRest }.count) sessions").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(preview) { day in
                HStack(alignment: .top, spacing: 12) {
                    Text(Weekday.shortNames[day.weekday])
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(day.weekday == Weekday.index(of: Date()) ? Theme.accentHighlight : Theme.textPrimary)
                        .frame(width: 38, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.isRest ? Theme.textTertiary : (day.keptAsIs ? Theme.textSecondary : Theme.accent))
                        .frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(day.name).font(.subheadline.weight(.semibold)).foregroundStyle(day.isRest ? Theme.textSecondary : Theme.textPrimary)
                            if day.keptAsIs { Tag(text: "Kept", color: Theme.textSecondary) }
                        }
                        if !day.muscles.isEmpty {
                            Text(day.muscles.prefix(5).map(\.shortName).joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        if let replacing = day.replacing {
                            Text("Replaces \(replacing)").font(.caption2).foregroundStyle(Theme.warning)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .primeCard(padding: 16)
    }
}
