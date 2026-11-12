import SwiftData
import SwiftUI

/// Short, skippable first run: what PRIME is, how ranking works, a few preferences,
/// an optional training split, optional bodyweight.
struct OnboardingFlow: View {
    enum Step: Int, CaseIterable {
        case welcome, ranking, profile, schedule, bodyweight, ready
    }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.motion) private var motion
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var name = ""
    @State private var unit: WeightUnit = Locale.current.measurementSystem == .us ? .lb : .kg
    @State private var system: MeasurementSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
    @State private var experience: ExperienceLevel = .beginner
    @State private var presetID: String?
    @State private var startDay = Weekday.index(of: Date())
    @State private var bodyweightText = ""
    @State private var bodyweightError: String?
    @State private var notificationsAsked = false
    @State private var emblemsShown = false
    @State private var logoIn = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if step != .welcome {
                    Button { go(back: true) } label: { Image(systemName: "chevron.left").font(.headline) }
                        .accessibilityLabel("Back")
                }
                ProgressBar(progress: Double(step.rawValue) / Double(Step.allCases.count - 1), height: 4)
                if step != .ready {
                    Button(step == .welcome ? "Skip setup" : "Skip") { skip() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 32)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)

            ZStack {
                page
                    .id(step)
                    .transition(motion.allowsMovement
                        ? .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                      removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
                        : .opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: next) { Text(primaryTitle) }
                .buttonStyle(.primePrimary)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 16)
        }
        .background {
            ZStack {
                Theme.backdrop
                AuroraBackdrop(intensity: step == .welcome || step == .ready ? 1 : 0.45)
            }
            .ignoresSafeArea()
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .schedule: return presetID == nil ? "Continue without a split" : "Use this split"
        case .ready: return "Start training"
        default: return "Continue"
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            VStack(spacing: 26) {
                Spacer()
                ZStack {
                    Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1).frame(width: 180, height: 180)
                        .scaleEffect(logoIn ? 1 : 0.6).opacity(logoIn ? 1 : 0)
                    Circle().strokeBorder(Theme.accent.opacity(0.12), lineWidth: 1).frame(width: 240, height: 240)
                        .scaleEffect(logoIn ? 1 : 0.5).opacity(logoIn ? 1 : 0)
                    PrimeMark().fill(Theme.accentGradient).frame(width: 104, height: 104)
                        .breathingGlow(Theme.accent, radius: 34)
                        .scaleEffect(logoIn ? 1 : 0.7)
                        .opacity(logoIn ? 1 : 0)
                }
                .onAppear { withAnimation(motion.animation(.spring(response: 0.8, dampingFraction: 0.7))) { logoIn = true } }
                VStack(spacing: 12) {
                    Text("PRIME").font(.system(size: 52, weight: .black).width(.condensed)).tracking(6).foregroundStyle(Theme.textPrimary)
                    Text("Plan your week. Log every set.\nLearn every lift. Earn every rank.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(spacing: 10) {
                    feature("calendar", "Training splits that fit your week")
                    feature("book.pages", "Step-by-step guides for every exercise")
                    feature("chart.xyaxis.line", "Records, analytics and progress insights")
                }
                Text("Works offline. No account needed.").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.gutter)

        case .ranking:
            question("Every lift has a rank", detail: "Each exercise climbs its own ladder from Unranked to Master. There's no single overall rank, because averaging a squat and a curl would be meaningless.") {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                        ForEach(Array(RankTier.allCases.enumerated()), id: \.element) { index, tier in
                            VStack(spacing: 6) {
                                RankEmblem(tier: tier, size: 54)
                                Text(tier.name).font(.caption2.weight(.semibold)).foregroundStyle(tier == .unranked ? Theme.textTertiary : tier.color)
                            }
                            .scaleEffect(emblemsShown || !motion.allowsMovement ? 1 : 0.4)
                            .opacity(emblemsShown ? 1 : 0)
                            .animation(motion.animation(.spring(response: 0.45, dampingFraction: 0.65)).map { $0.delay(Double(index) * 0.06) }, value: emblemsShown)
                        }
                    }
                    .onAppear { emblemsShown = true }
                    VStack(spacing: 10) {
                        infoRow("function", "Loaded lifts use an estimated one-rep max from a normal working set, divided by your bodyweight. You never have to max out.")
                        infoRow("figure.core.training", "Bodyweight moves rank on your best set of reps.")
                        infoRow("checkmark.seal", "Estimates are always labelled. Tiers are PRIME's own progression ladder, not an official standard.")
                    }
                }
            }

        case .profile:
            question("A few preferences", detail: "All optional, and all changeable later in Profile.") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").eyebrow()
                        TextField("Name or username", text: $name)
                            .font(.title3.weight(.semibold))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.field))
                            .focused($focused)
                            .submitLabel(.done)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units").eyebrow()
                        Picker("Weight", selection: $unit) {
                            ForEach(WeightUnit.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Measurements", selection: $system) {
                            ForEach(MeasurementSystem.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Experience").eyebrow()
                        VStack(spacing: 8) {
                            ForEach(ExperienceLevel.allCases) { option in
                                choiceRow(title: option.displayName, symbol: "figure.strengthtraining.traditional", selected: experience == option) { experience = option }
                            }
                        }
                    }
                }
            }

        case .schedule:
            question("Pick a training split", detail: "Optional. Choose a split and the day it starts; PRIME fills your week and you can edit everything afterwards.") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Starts on").eyebrow()
                        HStack(spacing: 6) {
                            ForEach(Weekday.all, id: \.self) { day in
                                Button {
                                    Haptics.selection()
                                    withAnimation(motion.animation(.snappy)) { startDay = day }
                                } label: {
                                    Text(Weekday.shortNames[day])
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(startDay == day ? Theme.onAccent : Theme.textSecondary)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(startDay == day ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(startDay == day ? .isSelected : [])
                            }
                        }
                    }
                    let recommended = SplitPreset.recommended(forDays: 4, experience: experience)
                    ForEach(SplitPreset.all) { preset in
                        let selected = presetID == preset.id
                        Button {
                            Haptics.selection()
                            withAnimation(motion.animation(.snappy)) { presetID = selected ? nil : preset.id }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: preset.symbol).foregroundStyle(Theme.accentHighlight).frame(width: 22)
                                    Text(preset.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    if preset.id == recommended { Tag(text: "Suggested", color: Theme.accentHighlight) }
                                    Spacer()
                                    Text("\(preset.sessionsPerWeek)×/wk").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                                }
                                if selected {
                                    Text(preset.summary).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                    PresetStrip(preset: preset, start: startDay)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

        case .bodyweight:
            question("Your bodyweight", detail: "Optional. Loaded lifts are ranked relative to bodyweight, so without it those ranks stay locked. You can add it later.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("0", text: $bodyweightText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 40, weight: .heavy).width(.condensed))
                            .focused($focused)
                            .onAppear { focused = true }
                        Text(unit.symbol).font(.title2.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.field))
                    if let bodyweightError { InlineError(message: bodyweightError) }
                }
            }

        case .ready:
            VStack(spacing: 22) {
                Spacer()
                RankEmblem(tier: .gold, size: 110)
                Text(trimmedName.isEmpty ? "You're set" : "You're set, \(trimmedName)")
                    .font(.primeLargeTitle).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                Text(presetID == nil
                     ? "Start an empty workout, browse the exercise library, or pick a split from Workouts whenever you're ready."
                     : "Your week is planned. Today's workout is waiting on Home.")
                    .font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                if !notificationsAsked {
                    Button {
                        notificationsAsked = true
                        Task {
                            let granted = await NotificationService.shared.requestAuthorization()
                            let profile = DataService.profile(in: context)
                            profile.notifyScheduledWorkouts = granted
                            profile.notifyRestTimer = granted
                            profile.notifyPersonalRecords = granted
                        }
                    } label: { Label("Allow workout and rest reminders", systemImage: "bell.badge") }
                        .buttonStyle(.primeSecondary)
                } else {
                    Label("You can change reminders in Profile", systemImage: "checkmark").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    // MARK: Building blocks

    private func question<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.primeLargeTitle).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private func choiceRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(selected ? Theme.onAccent : Theme.accent).frame(width: 24)
                Text(title).font(.headline).foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.headline).foregroundStyle(Theme.onAccent) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            IconBubble(symbol: symbol, size: 36)
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(symbol: symbol, size: 34)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    // MARK: Navigation

    private func next() {
        focused = false
        if step == .bodyweight, !bodyweightText.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .failure(let error) = InputValidator.bodyweight(bodyweightText, unit: unit) {
                bodyweightError = error.errorDescription
                Haptics.error()
                return
            }
        }
        if step == .ready {
            complete()
            return
        }
        go(back: false)
    }

    private func skip() {
        switch step {
        case .welcome:
            complete()
            return
        case .schedule: presetID = nil
        case .bodyweight: bodyweightText = ""; bodyweightError = nil
        default: break
        }
        go(back: false)
    }

    private func go(back: Bool) {
        focused = false
        let target = step.rawValue + (back ? -1 : 1)
        guard let nextStep = Step(rawValue: target) else { return }
        forward = !back
        withAnimation(motion.animation(.spring(response: 0.45, dampingFraction: 0.88)) ?? .easeInOut(duration: 0.2)) { step = nextStep }
    }

    private func complete() {
        let profile = DataService.profile(in: context)
        profile.name = trimmedName
        profile.weightUnit = unit
        profile.measurementSystem = system
        profile.experience = experience
        if case .success(let kilograms) = InputValidator.bodyweight(bodyweightText, unit: unit) {
            DataService.logBodyweight(kilograms, context: context)
        }
        if let presetID, let preset = SplitPreset.all.first(where: { $0.id == presetID }) {
            _ = ScheduleService.apply(preset, start: startDay, mode: .replace, exercises: exercises,
                                      restSeconds: profile.defaultRestSeconds, context: context)
            profile.weeklyGoal = max(1, preset.sessionsPerWeek)
            profile.preferredWeekdays = preset.layout(startingOn: startDay).compactMap { $0.value == nil ? nil : $0.key }.sorted()
        }
        profile.hasCompletedOnboarding = true
        try? context.save()
        store.refresh(context)
        appState.refreshNotifications(context: context, history: store.history)
        Haptics.success()
    }
}


/// Slow-moving soft blobs of navy and accent light. Cheap: three blurred circles on a timeline.
struct AuroraBackdrop: View {
    var intensity: Double = 1
    @Environment(\.motion) private var motion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !motion.allowsMovement)) { timeline in
            let t = motion.allowsMovement ? timeline.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    blob(Theme.accent.opacity(0.32 * intensity), size: w * 0.9)
                        .position(x: w * (0.3 + 0.12 * sin(t * 0.21)), y: h * (0.22 + 0.06 * cos(t * 0.17)))
                    blob(Theme.accentDeep.opacity(0.35 * intensity), size: w * 1.1)
                        .position(x: w * (0.75 + 0.1 * cos(t * 0.13)), y: h * (0.55 + 0.08 * sin(t * 0.19)))
                    blob(Theme.accentHighlight.opacity(0.14 * intensity), size: w * 0.7)
                        .position(x: w * (0.5 + 0.18 * sin(t * 0.11 + 1)), y: h * (0.85 + 0.05 * cos(t * 0.23)))
                }
            }
        }
        .blur(radius: 70)
        .animation(.easeInOut(duration: 0.6), value: intensity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}
