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
                                        if let heaviest = snapshot.heaviestWeightKg {
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
        let badges = BadgeEngine.globalBadges(history: store.history, bestStreak: best, recordCount: records.count,
                                              peakTier: rankings.map(\.tier).max(), unit: profile?.weightUnit ?? .kg)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BadgeGrid(title: "Milestones", badges: badges)
                Text("Every badge is earned from workouts you've logged. Exercise badges live on each lift's rank page.")
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
