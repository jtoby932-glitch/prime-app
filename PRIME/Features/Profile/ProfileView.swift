import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query private var records: [PersonalRecord]
    @Query private var rankings: [PerformanceRanking]
    @State private var photoItem: PhotosPickerItem?
    @State private var showBodyweight = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmErase = false
    @State private var confirmEraseAgain = false

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    content(profile)
                } else {
                    ProgressView()
                }
            }
            .primeBackground()
            .navigationTitle("Profile")
            .primeDestinations()
            .sheet(isPresented: $showBodyweight) { BodyweightEntrySheet().presentationDetents([.medium]) }
        }
    }

    private func content(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile
        let history = store.history
        let unit = profile.weightUnit
        let bestStreak = Analytics.bestWeekStreak(sessionDates: history.sessions.map(\.startedAt), weeklyGoal: profile.weeklyGoal)
        let peak = rankings.map(\.tier).max()

        return List {
            Section {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        AvatarView(data: profile.photoData, initials: profile.initials, size: 72)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.onAccent)
                                    .padding(6)
                                    .background(Circle().fill(Theme.accent))
                            }
                    }
                    .accessibilityLabel("Change profile photo")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Your name", text: $profile.name)
                            .font(.primeTitle)
                            .foregroundStyle(.white)
                            .submitLabel(.done)
                        Text("\(profile.experience.displayName) · since \(profile.createdAt.formatted(.dateTime.month(.abbreviated).year()))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 6)
                if profile.photoData != nil {
                    Button("Remove photo", role: .destructive) { profile.photoData = nil }
                        .font(.caption)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(count: history.sessions.count, label: "Workouts", symbol: "checkmark.seal.fill")
                    StatTile(value: Format.volume(Analytics.totalVolume(history.samples), unit: unit, includeUnit: false), label: "Total \(unit.symbol)", symbol: "scalemass.fill", tint: Theme.info)
                    StatTile(count: history.samples.count, label: "Working sets", symbol: "square.stack.3d.up.fill", tint: Theme.warning)
                    StatTile(count: bestStreak, label: "Best week streak", symbol: "flame.fill", tint: Theme.warning)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: { Text("Training statistics") }

            Section {
                NavigationLink(value: Route.analytics) { Label("Analytics", systemImage: "chart.xyaxis.line") }
                NavigationLink(value: Route.records) {
                    LabeledContent { Text("\(records.count)") } label: { Label("Personal records", systemImage: "trophy.fill") }
                }
                NavigationLink(value: Route.achievements) {
                    let earned = BadgeEngine.globalBadges(workouts: history.sessions.count, routineWorkouts: history.sessions.filter(\.fromRoutine).count,
                                                          bestStreak: bestStreak, recordCount: records.count, peakTier: peak).filter(\.isEarned).count
                    LabeledContent { Text("\(earned)") } label: { Label("Achievements", systemImage: "rosette") }
                }
                NavigationLink(value: Route.muscleMap) { Label("Muscle map", systemImage: "figure.arms.open") }
            }
            .listRowBackground(Theme.card)

            Section {
                NavigationLink(value: Route.bodyweight) {
                    LabeledContent {
                        Text(history.latestBodyweightKg.map { Format.weight($0, unit: unit) } ?? "Not set")
                    } label: { Label("Bodyweight", systemImage: "scalemass") }
                }
                Button { showBodyweight = true } label: { Label("Log bodyweight", systemImage: "plus") }
                if let height = profile.heightCm {
                    LabeledContent("Height", value: Format.height(cm: height, system: profile.measurementSystem))
                }
                HeightEditor(profile: profile)
            } header: { Text("Body") } footer: { Text("Optional. Bodyweight is only used to rank loaded lifts.") }
            .listRowBackground(Theme.card)

            Section("Units") {
                Picker("Weight", selection: $profile.weightUnitRaw) {
                    ForEach(WeightUnit.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                Picker("Measurements", selection: $profile.measurementSystemRaw) {
                    ForEach(MeasurementSystem.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            .listRowBackground(Theme.card)

            Section("Training") {
                Picker("Experience", selection: $profile.experienceRaw) {
                    ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                Stepper("Weekly goal: \(profile.weeklyGoal) workout\(profile.weeklyGoal == 1 ? "" : "s")", value: $profile.weeklyGoal, in: 1...7)
                Picker("Default rest", selection: $profile.defaultRestSeconds) {
                    ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240], id: \.self) { Text(Format.clock(TimeInterval($0))).tag($0) }
                }
                NavigationLink {
                    InterestsEditor(profile: profile)
                } label: {
                    LabeledContent("Interests", value: profile.interests.isEmpty ? "None" : "\(profile.interests.count) chosen")
                }
                NavigationLink {
                    PreferredDaysEditor(profile: profile)
                } label: {
                    LabeledContent("Preferred days", value: profile.preferredWeekdays.isEmpty ? "Any" : profile.preferredWeekdays.sorted().map { Weekday.shortNames[$0] }.joined(separator: " "))
                }
            }
            .listRowBackground(Theme.card)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tier scale")
                        Spacer()
                        Text(Format.percent(profile.tierScale)).monospacedDigit().foregroundStyle(Theme.accent)
                    }
                    Slider(value: $profile.tierScale, in: 0.5...1.5, step: 0.05) { editing in
                        if !editing { rebuildRanks(profile) }
                    }
                }
            } header: { Text("Rankings") } footer: {
                Text("Scales every provisional tier threshold. Lower it if the defaults feel too demanding for you, for example to account for sex, age or bodyweight. Exercises with your own tiers aren't affected.")
            }
            .listRowBackground(Theme.card)

            Section("App") {
                NavigationLink(value: Route.preferences) {
                    LabeledContent { Text(AnimationLevel(rawValue: profile.animationLevelRaw)?.displayName ?? "Full") } label: {
                        Label("Appearance and motion", systemImage: "paintbrush")
                    }
                }
                NavigationLink(value: Route.dashboardLayout) { Label("Dashboard layout", systemImage: "rectangle.3.group") }
                NavigationLink(value: Route.notifications) { Label("Notifications", systemImage: "bell.badge") }
                NavigationLink(value: Route.methodology) { Label("How ranking works", systemImage: "questionmark.circle") }
                NavigationLink(value: Route.licences) { Label("Licences", systemImage: "doc.plaintext") }
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    do { exportURL = try DataService.exportCSV(history: history, unit: unit) } catch { exportError = error.localizedDescription }
                } label: { Label("Export workout history (CSV)", systemImage: "tablecells") }
                    .disabled(history.isEmpty)
                Button {
                    do { exportURL = try DataService.exportJSON(context: context) } catch { exportError = error.localizedDescription }
                } label: { Label("Export everything (JSON)", systemImage: "curlybraces") }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share \(exportURL.lastPathComponent)", systemImage: "doc.text") }
                }
                if let exportError { InlineError(message: exportError) }
                Button(role: .destructive) { confirmErase = true } label: { Label("Erase all data", systemImage: "trash") }
            } header: { Text("Data") } footer: {
                Text("CSV is one row per set for spreadsheets. JSON includes routines, records, ranks and settings. Everything is stored on this iPhone and works offline. No account needed.\nPRIME \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item, into: profile) }
        }
        .onChange(of: profile.weightUnitRaw) { _, _ in try? context.save() }
        .confirmationDialog("Erase all PRIME data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { confirmEraseAgain = true }
        } message: {
            Text("Workouts, routines, records, bodyweight and settings will be deleted from this iPhone.")
        }
        .alert("This can't be undone", isPresented: $confirmEraseAgain) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) { erase() }
        } message: {
            Text("Export your history first if you might want it later.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?, into profile: UserProfile) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        // Store a small square JPEG, not the full-size original.
        let side: CGFloat = 400
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let resized = renderer.jpegData(withCompressionQuality: 0.85) { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        await MainActor.run {
            profile.photoData = resized
            try? context.save()
        }
    }

    private func rebuildRanks(_ profile: UserProfile) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        RecordService.rebuildAll(context: context, history: store.history, exercises: exercises, scale: profile.tierScale)
    }

    private func erase() {
        appState.activeSession = nil
        appState.coverSession = nil
        appState.isWorkoutPresented = false
        do {
            try DataService.eraseEverything(context: context)
        } catch {
            exportError = "Couldn't erase everything: \(error.localizedDescription)"
        }
        ScheduleService.ensureWeek(context: context)
        let fresh = DataService.profile(in: context)
        fresh.hasCompletedOnboarding = false
        try? context.save()
        store.refresh(context)
        appState.selectedTab = .home
    }
}

struct HeightEditor: View {
    @Bindable var profile: UserProfile
    @State private var editing = false
    @State private var cmText = ""
    @State private var feet = 5
    @State private var inches = 9

    var body: some View {
        Button(profile.heightCm == nil ? "Add height" : "Edit height") {
            if let cm = profile.heightCm {
                cmText = String(Int(cm.rounded()))
                let parts = HeightConversion.feetAndInches(fromCentimetres: cm)
                feet = parts.feet
                inches = parts.inches
            }
            editing = true
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    if profile.measurementSystem == .metric {
                        TextField("Height in cm", text: $cmText).keyboardType(.numberPad)
                    } else {
                        Picker("Feet", selection: $feet) { ForEach(3...8, id: \.self) { Text("\($0) ft").tag($0) } }
                        Picker("Inches", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) } }
                    }
                    if profile.heightCm != nil {
                        Button("Remove height", role: .destructive) { profile.heightCm = nil; editing = false }
                    }
                }
                .navigationTitle("Height")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if profile.measurementSystem == .metric {
                                if let value = InputValidator.parseNumber(cmText), (90...250).contains(value) { profile.heightCm = value } else { return }
                            } else {
                                profile.heightCm = HeightConversion.centimetres(feet: feet, inches: inches)
                            }
                            editing = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

struct InterestsEditor: View {
    @Bindable var profile: UserProfile

    var body: some View {
        List(TrainingInterest.allCases) { interest in
            Button {
                var current = profile.interests
                if let index = current.firstIndex(of: interest) { current.remove(at: index) } else { current.append(interest) }
                profile.interests = current
            } label: {
                HStack {
                    Label(interest.displayName, systemImage: interest.symbol).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if profile.interests.contains(interest) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .navigationTitle("Interests")
    }
}

struct PreferredDaysEditor: View {
    @Bindable var profile: UserProfile

    var body: some View {
        List(Weekday.all, id: \.self) { day in
            Button {
                var days = Set(profile.preferredWeekdays)
                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                profile.preferredWeekdays = days.sorted()
            } label: {
                HStack {
                    Text(Weekday.longNames[day]).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if profile.preferredWeekdays.contains(day) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .primeBackground()
        .navigationTitle("Preferred days")
    }
}
