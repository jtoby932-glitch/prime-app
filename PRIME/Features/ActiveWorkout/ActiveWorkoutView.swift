import SwiftData
import SwiftUI

enum SetField: Hashable {
    case weight(PersistentIdentifier)
    case reps(PersistentIdentifier)
}

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @FocusState private var focus: SetField?
    @State private var showAddExercise = false
    @State private var replaceTarget: ExerciseSession?
    @State private var notesTarget: ExerciseSession?
    @State private var guideTarget: Exercise?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var burst = 0

    private var profile: UserProfile? { profiles.first }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    WorkoutHeader(session: session, unit: unit)
                    ReadinessPicker(session: session)
                    if session.exercises.isEmpty {
                        EmptyStateView(symbol: "plus.circle", title: "Add your first exercise",
                                       message: "Pick from the library. PRIME will fill in what you did last time.",
                                       actionTitle: "Add exercise") { showAddExercise = true }
                            .primeCard()
                    }
                    ForEach(session.sortedExercises) { item in
                        ExerciseCard(
                            item: item, session: session, unit: unit, focus: $focus,
                            onReplace: { replaceTarget = item },
                            onNotes: { notesTarget = item },
                            onGuide: { guideTarget = item.exercise },
                            onRecord: celebrate
                        )
                    }
                    Button { showAddExercise = true } label: {
                        Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prime(.quiet))
                    HStack(spacing: 10) {
                        Button("Discard") { confirmDiscard = true }.buttonStyle(.primeDestructive)
                        Button("Finish workout") { requestFinish() }.buttonStyle(.primePrimary)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .primeBackground()
            .overlay { RecordBurst(trigger: burst) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.restEndsAt != nil || session.restPausedRemaining != nil {
                    RestTimerBar(session: session, notify: profile?.notifyRestTimer ?? true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: session.restEndsAt != nil || session.restPausedRemaining != nil)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        focus = nil
                        appState.isWorkoutPresented = false
                    } label: { Image(systemName: "chevron.down").font(.headline) }
                        .accessibilityLabel("Minimise workout")
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        renameText = session.name
                        isRenaming = true
                    } label: {
                        VStack(spacing: 0) {
                            Text(session.name).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                            TimelineView(.periodic(from: session.startedAt, by: 1)) { timeline in
                                Text(Format.clock(timeline.date.timeIntervalSince(session.startedAt)))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .accessibilityLabel("Workout name, \(session.name). Tap to rename.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { requestFinish() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button { moveFocus(by: -1) } label: { Image(systemName: "chevron.up") }
                    Button { moveFocus(by: 1) } label: { Image(systemName: "chevron.down") }
                    Spacer()
                    Button("Done") { focus = nil }.fontWeight(.bold)
                }
            }
            .primeDestinations()
            .overlay(alignment: .top) { ToastOverlay() }
        }
        .restTimerCompletion(session: session)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showAddExercise) {
            ExercisePickerView(mode: .multiple, title: "Add exercises") { picked in
                for exercise in picked {
                    WorkoutService.addExercise(exercise, to: session, restSeconds: restSeconds(for: exercise), context: context, history: store.history)
                }
            }
        }
        .sheet(item: $replaceTarget) { item in
            ExercisePickerView(mode: .single, title: "Replace \(item.exerciseName)", excluding: [item.exerciseSlug]) { picked in
                if let exercise = picked.first {
                    WorkoutService.replace(item, with: exercise, context: context)
                    Haptics.success()
                }
            }
        }
        .sheet(item: $guideTarget) { exercise in
            ExerciseGuideSheet(exercise: exercise).presentationDetents([.medium, .large])
        }
        .sheet(item: $notesTarget) { item in
            ExerciseNotesSheet(item: item).presentationDetents([.medium])
        }
        .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout") { finish() }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text(WorkoutService.hasIncompleteSetsWithValues(session)
                 ? "Sets you haven't ticked off will be removed."
                 : "\(session.completedSets.count) sets · \(Format.volume(session.totalVolume, unit: unit))")
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) {
                appState.discardWorkout(session, context: context)
            }
        } message: {
            Text("Nothing from this session will be saved.")
        }
        .alert("Can't finish yet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
            Button("Discard workout", role: .destructive) {
                appState.discardWorkout(session, context: context)
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename workout", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { session.name = trimmed; try? context.save() }
            }
        }
    }

    private func restSeconds(for exercise: Exercise) -> Int {
        let base = profile?.defaultRestSeconds ?? 90
        return exercise.mechanic == .compound ? max(base, 120) : base
    }

    private func requestFinish() {
        focus = nil
        if session.completedSets.isEmpty {
            errorMessage = WorkoutError.noCompletedSets.errorDescription
            Haptics.warning()
        } else {
            confirmFinish = true
        }
    }

    private func finish() {
        do {
            let summary = try WorkoutService.finish(session, context: context, store: store, profile: profile, exercises: exercises)
            Haptics.success()
            appState.endWorkout(summary: summary)
            appState.refreshNotifications(context: context, history: store.history)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func celebrate(_ kinds: [RecordKind], _ item: ExerciseSession) {
        guard let first = kinds.first else { return }
        Haptics.record()
        burst += 1
        let names = kinds.map(\.displayName).joined(separator: " · ")
        appState.show(Toast(title: "New record · \(item.exerciseName)", message: kinds.count > 1 ? names : first.displayName, style: .record))
    }

    /// Ordered list of every editable field, for the keyboard's previous/next buttons.
    private var orderedFields: [SetField] {
        session.sortedExercises.filter { !$0.isSkipped }.flatMap { item in
            item.sortedSets.filter { !$0.isCompleted }.flatMap { [SetField.weight($0.persistentModelID), .reps($0.persistentModelID)] }
        }
    }

    private func moveFocus(by offset: Int) {
        let fields = orderedFields
        guard let current = focus, let index = fields.firstIndex(of: current) else {
            focus = fields.first
            return
        }
        let next = index + offset
        focus = fields.indices.contains(next) ? fields[next] : nil
    }
}

// MARK: - Header

struct WorkoutHeader: View {
    let session: WorkoutSession
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: session.completion, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(Format.percent(session.completion))
                        .font(.primeNumber(17)).foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: session.completion)
                    Text("done").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    metric(title: "Duration") {
                        TimelineView(.periodic(from: session.startedAt, by: 1)) { timeline in
                            Text(Format.clock(timeline.date.timeIntervalSince(session.startedAt)))
                        }
                    }
                    metric(title: "Volume") {
                        Text(Format.volume(session.totalVolume, unit: unit, includeUnit: false))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: session.totalVolume)
                    }
                    metric(title: "Sets") {
                        Text("\(session.completedSets.count)")
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: session.completedSets.count)
                    }
                }
                Text("Volume in \(unit.symbol) · \(session.exercises.count) exercise\(session.exercises.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .primeHero(tint: Theme.accent, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func metric<Content: View>(title: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value()
                .font(.primeNumber(24))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Notes

struct ExerciseNotesSheet: View {
    @Bindable var item: ExerciseSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            TextEditor(text: $item.notes)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                .padding()
                .background(Theme.surface.ignoresSafeArea())
                .navigationTitle("Notes · \(item.exerciseName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            try? context.save()
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
        }
    }
}

// MARK: - Rest timer

struct RestTimerBar: View {
    @Bindable var session: WorkoutSession
    let notify: Bool
    @Environment(\.motion) private var motion

    private static let presets = [30, 60, 90, 120, 150, 180, 240]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let paused = session.restPausedRemaining != nil
            let remaining = paused ? Double(session.restPausedRemaining ?? 0) : max(0, (session.restEndsAt ?? timeline.date).timeIntervalSince(timeline.date))
            let total = max(1, Double(session.restTotalSeconds))
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.field, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, remaining / total)))
                        .stroke(paused ? AnyShapeStyle(Theme.textSecondary) : AnyShapeStyle(Theme.accentGradient), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(motion.allowsAnimation ? .linear(duration: 0.25) : nil, value: remaining)
                    Button {
                        if paused { WorkoutService.resumeRest(session, notify: notify) } else { WorkoutService.pauseRest(session) }
                        Haptics.tap()
                    } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill").font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityLabel(paused ? "Resume rest timer" : "Pause rest timer")
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.clock(remaining.rounded(.up)))
                        .font(.primeNumber(26))
                        .foregroundStyle(paused ? Theme.textSecondary : Theme.textPrimary)
                        .contentTransition(.numericText(countsDown: true))
                    Menu {
                        ForEach(Self.presets, id: \.self) { seconds in
                            Button("Restart at \(Format.clock(TimeInterval(seconds)))") { WorkoutService.setRest(session, seconds: seconds, notify: notify) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(paused ? "Paused" : (session.restExerciseName.isEmpty ? "Rest" : "Rest · \(session.restExerciseName)"))
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Rest presets")
                }
                Spacer(minLength: 4)
                timerButton("−15") { WorkoutService.adjustRest(session, by: -15, notify: notify) }
                    .disabled(paused)
                timerButton("+15") { WorkoutService.adjustRest(session, by: 15, notify: notify) }
                    .disabled(paused)
                Button("Skip") { WorkoutService.endRest(session) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentGradient))
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(paused ? "Rest timer paused, \(Int(remaining)) seconds left" : "Rest timer, \(Int(remaining)) seconds left")
        }
    }

    private func timerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
        }
    }
}

/// Optional, subjective readiness for this session. Personal tracking only; it never changes the plan.
struct ReadinessPicker: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context

    private static let labels = ["Drained", "Low", "OK", "Good", "Great"]

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How ready do you feel?").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Text(session.readiness.map { Self.labels[$0 - 1] } ?? "Optional").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            ForEach(1...5, id: \.self) { value in
                let selected = session.readiness == value
                Button {
                    session.readiness = selected ? nil : value
                    try? context.save()
                    Haptics.selection()
                } label: {
                    Text("\(value)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 30, height: 30)
                        .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                        .background(Circle().fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.field)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Readiness \(value) of 5, \(Self.labels[value - 1])")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Ends the rest timer on time with a haptic, whether the workout is open or minimised.
struct RestTimerCompletion: ViewModifier {
    let session: WorkoutSession

    func body(content: Content) -> some View {
        content.task(id: session.restEndsAt) {
            guard let end = session.restEndsAt else { return }
            let delay = end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, session.restEndsAt == end else { return }
            if delay > -2 { Haptics.success() }
            session.restEndsAt = nil
        }
    }
}

extension View {
    func restTimerCompletion(session: WorkoutSession) -> some View { modifier(RestTimerCompletion(session: session)) }
}

// MARK: - Minimised bar

struct ActiveWorkoutBar: View {
    let session: WorkoutSession
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.isWorkoutPresented = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "bolt.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.onAccent)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        if let end = session.restEndsAt, end > timeline.date {
                            Text("Resting · \(Format.clock(end.timeIntervalSince(timeline.date).rounded(.up)))")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                        } else {
                            Text("\(Format.clock(timeline.date.timeIntervalSince(session.startedAt))) · \(session.completedSets.count) sets")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.up").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        }
        .buttonStyle(PressableStyle())
        .restTimerCompletion(session: session)
        .accessibilityLabel("Workout in progress: \(session.name). Open.")
    }
}


/// A short gold burst from the centre of the screen when a record is set. Never blocks touches.
struct RecordBurst: View {
    let trigger: Int
    @Environment(\.motion) private var motion
    @State private var fired = 0
    @State private var progress: CGFloat = 0

    private let count = 18

    var body: some View {
        GeometryReader { proxy in
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.4)
            ZStack {
                if fired > 0 && progress < 1 {
                    Circle()
                        .stroke(Theme.warning.opacity(0.6 * (1 - progress)), lineWidth: 2)
                        .frame(width: 40 + 260 * progress, height: 40 + 260 * progress)
                        .position(centre)
                    ForEach(0..<count, id: \.self) { index in
                        let angle = Double(index) / Double(count) * 2 * .pi
                        let distance = (60 + 120 * progress) * (index.isMultiple(of: 2) ? 1 : 0.75)
                        Circle()
                            .fill(index.isMultiple(of: 3) ? Theme.warning : Color(hex: 0xFFE08A))
                            .frame(width: 6 - 3 * progress, height: 6 - 3 * progress)
                            .position(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance - 40 * progress * progress)
                            .opacity(1 - progress)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) { _, value in
            guard motion.allowsMovement else { return }
            fired = value
            progress = 0
            withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
        }
    }
}
