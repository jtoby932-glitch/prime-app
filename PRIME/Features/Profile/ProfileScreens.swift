import Charts
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Bodyweight

struct BodyweightView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store
    @Query(sort: \BodyweightEntry.date, order: .reverse) private var entries: [BodyweightEntry]
    @Query private var profiles: [UserProfile]
    @State private var showEntry = false

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        List {
            if entries.count >= 2 {
                Section {
                    Chart(entries) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("Weight", unit.fromKilograms(entry.weightKg)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", entry.date), y: .value("Weight", unit.fromKilograms(entry.weightKg)))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(16)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(Theme.stroke)
                            AxisValueLabel().foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Theme.card)
            }
            Section {
                if entries.isEmpty {
                    Text("No entries yet. Bodyweight is optional; it's used to rank loaded lifts relative to your size.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Format.weight(entry.weightKg, unit: unit)).font(.body.weight(.semibold).monospacedDigit())
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(entries[index]) }
                    try? context.save()
                    store.refresh(context)
                }
            } header: { Text("History") } footer: {
                Text("Each workout ranks against the bodyweight logged nearest to it.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .navigationTitle("Bodyweight")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEntry = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log bodyweight")
            }
        }
        .sheet(isPresented: $showEntry) { BodyweightEntrySheet().presentationDetents([.medium]) }
    }
}

struct BodyweightEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @State private var text = ""
    @State private var date = Date()
    @State private var error: String?
    @FocusState private var focused: Bool

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Bodyweight", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .focused($focused)
                        Text(unit.symbol).foregroundStyle(Theme.textSecondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if let error { Section { InlineError(message: error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Log bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
            .onAppear {
                if let latest = store.history.latestBodyweightKg { text = Format.number(unit.fromKilograms(latest), maxFractionDigits: 1) }
                focused = true
            }
        }
    }

    private func save() {
        switch InputValidator.bodyweight(text, unit: unit) {
        case .success(let kilograms):
            DataService.logBodyweight(kilograms, on: date, context: context)
            store.refresh(context)
            Haptics.success()
            dismiss()
        case .failure(let failure):
            error = failure.errorDescription
            Haptics.error()
        }
    }
}

// MARK: - Records

struct PersonalRecordsView: View {
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query private var profiles: [UserProfile]
    @Environment(TrainingStore.self) private var store
    @State private var kind: RecordKind?

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }

    var body: some View {
        let filtered = records.filter { kind == nil || $0.kind == kind }
        let slugs = store.history.exerciseSlugsByRecency
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !slugs.isEmpty {
                    SectionHeader(title: "Current bests")
                    VStack(spacing: 8) {
                        ForEach(slugs, id: \.self) { slug in
                            let snapshot = store.history.records(for: slug)
                            NavigationLink(value: Route.exercise(slug)) {
                                HStack {
                                    Text(store.history.exerciseName(for: slug) ?? slug).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let e1rm = snapshot.bestOneRepMaxKg {
                                            Text("e1RM \(Format.estimate(e1rm, unit: unit))").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                        }
                                        if let hold = snapshot.longestHoldSeconds {
                                            Text("Longest \(Format.hold(hold))").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                        } else if let heaviest = snapshot.heaviestWeightKg {
                                            Text("Heaviest \(Format.weight(heaviest, unit: unit))").font(.caption).foregroundStyle(Theme.textSecondary)
                                        } else if let reps = snapshot.mostRepsByWeight.values.max() {
                                            Text("\(reps) reps").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                        }
                                    }
                                }
                                .primeCard(padding: 12)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }

                SectionHeader(title: "Record timeline")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "All", isSelected: kind == nil) { kind = nil }
                        ForEach(RecordKind.allCases) { option in
                            Chip(title: option.displayName, isSelected: kind == option) { kind = option }
                        }
                    }
                }
                if filtered.isEmpty {
                    EmptyStateView(symbol: "trophy", title: "No records yet",
                                   message: "Your first session with a lift sets its baseline. Beat it next time and the record lands here.")
                        .primeCard()
                }
                VStack(spacing: 8) {
                    ForEach(filtered) { record in
                        NavigationLink(value: Route.exercise(record.exerciseSlug)) {
                            RecordRow(record: record, unit: unit).primeCard(padding: 12)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle("Personal records")
    }
}

// MARK: - Achievements

struct AchievementsView: View {
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query private var records: [PersonalRecord]
    @Query private var rankings: [PerformanceRanking]

    var body: some View {
        let profile = profiles.first
        let best = Analytics.bestWeekStreak(sessionDates: store.history.sessions.map(\.startedAt), weeklyGoal: profile?.weeklyGoal ?? 3)
        let badges = BadgeEngine.globalBadges(workouts: store.history.sessions.count,
                                              routineWorkouts: store.history.sessions.filter(\.fromRoutine).count,
                                              bestStreak: best, recordCount: records.count, peakTier: rankings.map(\.tier).max())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BadgeGrid(title: "Milestones", badges: badges)
                Text("Every badge is earned from workouts you've logged. None reward piling on extra volume. Exercise badges live on each lift's rank page.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle("Achievements")
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [UserProfile]
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            if let profile = profiles.first {
                form(profile)
            }
        }
        .navigationTitle("Notifications")
        .task { status = await NotificationService.shared.authorizationStatus() }
    }

    private func form(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return Form {
            if status == .denied {
                Section {
                    Text("Notifications are turned off for PRIME in iOS Settings.").foregroundStyle(Theme.warning)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } else if status == .notDetermined {
                Section {
                    Button("Allow notifications") {
                        Task { status = await NotificationService.shared.requestAuthorization() ? .authorized : .denied }
                    }
                } footer: { Text("PRIME only sends the kinds you switch on below.") }
            }
            Section {
                Toggle("Scheduled workouts", isOn: $profile.notifyScheduledWorkouts)
                if profile.notifyScheduledWorkouts {
                    DatePicker("Remind me at", selection: timeBinding($profile.scheduledReminderMinutes), displayedComponents: .hourAndMinute)
                }
            } footer: { Text("A reminder on days your timetable has a workout.") }
            Section {
                Toggle("Missed workout nudge", isOn: $profile.notifyMissedWorkouts)
                if profile.notifyMissedWorkouts {
                    DatePicker("If not done by", selection: timeBinding($profile.missedReminderMinutes), displayedComponents: .hourAndMinute)
                }
            } footer: { Text("Only sent on planned days when you haven't logged a workout yet.") }
            Section {
                Toggle("Rest timer finished", isOn: $profile.notifyRestTimer)
                Toggle("Personal records", isOn: $profile.notifyPersonalRecords)
            } footer: { Text("Rest alerts reach you when PRIME is in the background. Record alerts summarise new bests after a workout.") }
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .onChange(of: profile.notifyScheduledWorkouts) { _, on in if on { ensurePermission() }; refresh() }
        .onChange(of: profile.notifyMissedWorkouts) { _, on in if on { ensurePermission() }; refresh() }
        .onChange(of: profile.notifyRestTimer) { _, on in if on { ensurePermission() } }
        .onChange(of: profile.notifyPersonalRecords) { _, on in if on { ensurePermission() } }
        .onChange(of: profile.scheduledReminderMinutes) { _, _ in refresh() }
        .onChange(of: profile.missedReminderMinutes) { _, _ in refresh() }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.prime.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.prime.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func ensurePermission() {
        guard status == .notDetermined else { return }
        Task { status = await NotificationService.shared.requestAuthorization() ? .authorized : .denied }
    }

    private func refresh() {
        try? context.save()
        appState.refreshNotifications(context: context, history: store.history)
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first { form(profile) }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func form(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return Form {
            Section {
                Picker("Animations", selection: $profile.animationLevelRaw) {
                    ForEach(AnimationLevel.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                Toggle("Haptic feedback", isOn: $profile.hapticsEnabled)
            } header: { Text("Motion and feel") } footer: {
                Text("Reduced keeps fades but drops movement and particles. iOS Reduce Motion always wins, whatever you pick here.")
            }
            Section {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        profile.accentRaw = choice.rawValue
                        try? context.save()
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(LinearGradient(colors: [choice.highlight, choice.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 26, height: 26)
                            Text(choice.displayName).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if profile.accentRaw == choice.rawValue { Image(systemName: "checkmark").foregroundStyle(choice.base) }
                        }
                    }
                }
            } header: { Text("Accent colour") } footer: { Text("PRIME is always dark: black and navy with one accent.") }
            Section {
                Picker("Anatomy figure", selection: $profile.bodyModelRaw) {
                    ForEach(BodyModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
            } header: { Text("Anatomy") } footer: { Text("Used by the muscle map and exercise illustrations.") }
            Section("Home") {
                NavigationLink(value: Route.dashboardLayout) { Label("Dashboard layout", systemImage: "rectangle.3.group") }
            }
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .onChange(of: profile.hapticsEnabled) { _, on in
            Haptics.enabled = on
            try? context.save()
        }
        .onChange(of: profile.animationLevelRaw) { _, _ in try? context.save() }
        .onChange(of: profile.bodyModelRaw) { _, _ in try? context.save() }
    }
}

// MARK: - Dashboard layout

struct DashboardLayoutView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first { list(profile) }
        }
        .navigationTitle("Dashboard layout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(_ profile: UserProfile) -> some View {
        let order = DashboardSection.ordered(order: profile.dashboardOrder, hidden: [])
        return List {
            Section {
                ForEach(order) { section in
                    let hidden = profile.dashboardHidden.contains(section.rawValue)
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol).foregroundStyle(hidden ? Theme.textTertiary : Theme.accentHighlight).frame(width: 24)
                        Text(section.title).foregroundStyle(hidden ? Theme.textTertiary : Theme.textPrimary)
                        Spacer()
                        Button {
                            toggle(section, in: profile)
                        } label: {
                            Image(systemName: hidden ? "eye.slash" : "eye").foregroundStyle(hidden ? Theme.textTertiary : Theme.accent)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(hidden ? "Show \(section.title)" : "Hide \(section.title)")
                    }
                }
                .onMove { source, destination in
                    var items = order.map(\.rawValue)
                    items.move(fromOffsets: source, toOffset: destination)
                    profile.dashboardOrder = items
                    try? context.save()
                }
            } footer: {
                Text("Drag to reorder. The greeting and today's workout always stay at the top.")
            }
            .listRowBackground(Theme.card)
            Section {
                Button("Reset to default") {
                    profile.dashboardOrder = []
                    profile.dashboardHidden = []
                    try? context.save()
                }
            }
            .listRowBackground(Theme.card)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .primeBackground()
    }

    private func toggle(_ section: DashboardSection, in profile: UserProfile) {
        var hidden = profile.dashboardHidden
        if let index = hidden.firstIndex(of: section.rawValue) { hidden.remove(at: index) } else { hidden.append(section.rawValue) }
        profile.dashboardHidden = hidden
        Haptics.selection()
        try? context.save()
    }
}

// MARK: - Licences

struct LicencesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anatomy artwork").font(.primeTitle3).foregroundStyle(Theme.textPrimary)
                    Text(AnatomyFigure.credit).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text("Muscle regions were remapped to PRIME's muscle groups and redrawn natively.").font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .primeCard(padding: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MIT License").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(Self.mit).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .primeCard(padding: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise guides and rankings").font(.primeTitle3).foregroundStyle(Theme.textPrimary)
                    Text("Written for PRIME. Tier thresholds are PRIME's own progression system, not an official strength standard.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .primeCard(padding: 16)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .primeBackground()
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let mit = """
    Copyright (c) 2022 ELABBASSI Hicham

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
