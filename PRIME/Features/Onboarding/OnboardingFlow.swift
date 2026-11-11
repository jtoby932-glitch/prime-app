import SwiftData
import SwiftUI
import UserNotifications

struct OnboardingFlow: View {
    enum Step: Int, CaseIterable {
        case welcome, name, units, experience, interests, days, bodyweight, notifications, ready

        var isOptional: Bool {
            switch self {
            case .welcome, .units, .ready: return false
            default: return true
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var name = ""
    @State private var unit: WeightUnit = Locale.current.measurementSystem == .us ? .lb : .kg
    @State private var system: MeasurementSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
    @State private var experience: ExperienceLevel?
    @State private var interests: Set<TrainingInterest> = []
    @State private var days: Set<Int> = []
    @State private var bodyweightText = ""
    @State private var bodyweightError: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                HStack(spacing: 12) {
                    Button { go(back: true) } label: { Image(systemName: "chevron.left").font(.headline) }
                        .accessibilityLabel("Back")
                    ProgressBar(progress: Double(step.rawValue) / Double(Step.allCases.count - 1), height: 4)
                    if step.isOptional {
                        Button("Skip") { skip() }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
            }

            ZStack {
                page
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: next) {
                Text(primaryTitle)
            }
            .buttonStyle(.primePrimary)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .notifications: return "Continue"
        case .ready: return "Build my first week"
        default: return "Continue"
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.08)).frame(width: 260, height: 260).blur(radius: 30)
                    PrimeMark().fill(Theme.accentGradient).frame(width: 110, height: 110)
                }
                VStack(spacing: 12) {
                    Text("PRIME").font(.system(size: 54, weight: .black).width(.condensed)).tracking(4).foregroundStyle(.white)
                    Text("Plan your week. Log every set.\nWatch every lift climb the ranks.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: 18) {
                    feature("calendar", "Timetable")
                    feature("bolt.fill", "Tracking")
                    feature("shield.lefthalf.filled", "Rankings")
                    feature("chart.xyaxis.line", "Analytics")
                }
                Text("Works offline. No account needed.").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.gutter)

        case .name:
            question("What should we call you?", detail: "Used for your greeting. Stays on this iPhone.") {
                TextField("Name or username", text: $name)
                    .font(.title2.weight(.bold))
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.field))
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit(next)
                    .onAppear { focused = true }
            }

        case .units:
            question("Pick your units", detail: "You can switch any time. Everything converts automatically.") {
                VStack(spacing: 10) {
                    ForEach(WeightUnit.allCases) { option in
                        choiceRow(title: option.displayName, symbol: "scalemass.fill", selected: unit == option) { unit = option }
                    }
                    DividerLine().padding(.vertical, 6)
                    ForEach(MeasurementSystem.allCases) { option in
                        choiceRow(title: option.displayName, symbol: "ruler.fill", selected: system == option) { system = option }
                    }
                }
            }

        case .experience:
            question("How long have you been lifting?", detail: "Helps PRIME suggest a sensible starting plan.") {
                VStack(spacing: 10) {
                    ForEach(ExperienceLevel.allCases) { option in
                        choiceRow(title: option.displayName, symbol: "figure.strengthtraining.traditional", selected: experience == option) { experience = option }
                    }
                }
            }

        case .interests:
            question("What are you training for?", detail: "Pick as many as you like.") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(TrainingInterest.allCases) { interest in
                        let selected = interests.contains(interest)
                        Button {
                            if selected { interests.remove(interest) } else { interests.insert(interest) }
                            Haptics.selection()
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: interest.symbol).font(.title3).foregroundStyle(selected ? Theme.onAccent : Theme.accent)
                                Text(interest.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(selected ? Theme.onAccent : .white)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18).fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

        case .days:
            question("Which days can you train?", detail: "We'll build your timetable around them. Rest days matter too.") {
                VStack(spacing: 8) {
                    ForEach(Weekday.all, id: \.self) { day in
                        choiceRow(title: Weekday.longNames[day], symbol: days.contains(day) ? "checkmark.circle.fill" : "circle", selected: days.contains(day)) {
                            if days.contains(day) { days.remove(day) } else { days.insert(day) }
                        }
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

        case .notifications:
            question("Stay on schedule", detail: "PRIME can remind you on training days and tell you when rest is over. You choose exactly which alerts you get in Profile.") {
                VStack(spacing: 10) {
                    infoRow("calendar.badge.clock", "Workout reminders on your planned days")
                    infoRow("timer", "Rest timer alerts when PRIME is in the background")
                    infoRow("trophy.fill", "A summary when you set a new record")
                    Button("Allow notifications") {
                        Task {
                            let granted = await NotificationService.shared.requestAuthorization()
                            if let profile = profiles.first {
                                profile.notifyScheduledWorkouts = granted
                                profile.notifyRestTimer = granted
                                profile.notifyPersonalRecords = granted
                            }
                            next()
                        }
                    }
                    .buttonStyle(.primeSecondary)
                    .padding(.top, 8)
                }
            }

        case .ready:
            VStack(spacing: 22) {
                Spacer()
                TierBadgeView(tier: .elite, size: 110)
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "You're set" : "You're set, \(name.trimmingCharacters(in: .whitespaces))")
                    .font(.primeLargeTitle).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Next, pick a starter plan or build your own routine. Every lift you log earns a rank from Beginner to Elite.")
                    .font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Spacer()
                Button("I'll explore first") { complete(openGuide: false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: Building blocks

    private func question<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.primeLargeTitle).foregroundStyle(.white)
                    Text(detail).font(.body).foregroundStyle(Theme.textSecondary)
                }
                content()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func choiceRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(selected ? Theme.onAccent : Theme.accent).frame(width: 24)
                Text(title).font(.headline).foregroundStyle(selected ? Theme.onAccent : .white)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.headline).foregroundStyle(Theme.onAccent) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            IconBubble(symbol: symbol, size: 44)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            IconBubble(symbol: symbol, size: 38)
            Text(text).font(.subheadline).foregroundStyle(.white)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
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
            complete(openGuide: true)
            return
        }
        go(back: false)
    }

    private func skip() {
        switch step {
        case .name: name = ""
        case .experience: experience = nil
        case .interests: interests = []
        case .days: days = []
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
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.88)) { step = nextStep }
    }

    private func complete(openGuide: Bool) {
        let profile = DataService.profile(in: context)
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.weightUnit = unit
        profile.measurementSystem = system
        if let experience { profile.experience = experience }
        profile.interests = TrainingInterest.allCases.filter { interests.contains($0) }
        profile.preferredWeekdays = days.sorted()
        if !days.isEmpty { profile.weeklyGoal = days.count }
        if case .success(let kilograms) = InputValidator.bodyweight(bodyweightText, unit: unit) {
            DataService.logBodyweight(kilograms, context: context)
        }
        profile.hasCompletedOnboarding = true
        try? context.save()
        store.refresh(context)
        appState.refreshNotifications(context: context, history: store.history)
        if openGuide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { appState.showFirstWorkoutGuide = true }
        }
        Haptics.success()
    }
}
