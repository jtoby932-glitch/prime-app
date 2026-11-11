import Charts
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]

    private var profile: UserProfile? { profiles.first }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }
    private var history: TrainingHistory { store.history }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if history.isEmpty && plans.isEmpty {
                        GetStartedCard()
                    }
                    TodayCard(days: days, unit: unit)
                    WeekProgressCard(days: days, weeklyGoal: profile?.weeklyGoal ?? 3)
                    statsRow
                    if !history.isEmpty {
                        WeeklyVolumeCard(unit: unit)
                        RecentRecordsCard(records: Array(records.prefix(3)), unit: unit)
                        RecentPerformanceCard(unit: unit)
                    }
                    shortcuts
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .primeBackground()
            .toolbar(.hidden, for: .navigationBar)
            .primeDestinations()
            .workoutBarInset()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .eyebrow()
                Text("\(greeting), \(profile?.displayName ?? "Athlete")")
                    .font(.primeLargeTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Button {
                appState.selectedTab = .profile
            } label: {
                AvatarView(data: profile?.photoData, initials: profile?.initials ?? "", size: 44)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Profile")
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        switch Calendar.prime.component(.hour, from: Date()) {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }

    private var statsRow: some View {
        let dates = history.sessions.map(\.startedAt)
        let streak = Analytics.weekStreak(sessionDates: dates, weeklyGoal: profile?.weeklyGoal ?? 3)
        let weekInterval = DateInterval(start: Calendar.prime.startOfWeek(for: Date()), end: Date())
        let weekVolume = Analytics.totalVolume(history.samples(in: weekInterval))
        return HStack(spacing: 10) {
            StatTile(value: "\(streak)", label: "Week streak", symbol: "flame.fill", tint: Theme.warning)
            StatTile(value: "\(history.sessions.count)", label: "Workouts", symbol: "checkmark.seal.fill")
            StatTile(value: Format.volume(weekVolume, unit: unit, includeUnit: false), label: "\(unit.symbol) this week", symbol: "chart.bar.fill", tint: Theme.info)
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.analytics) {
                ShortcutTile(symbol: "chart.xyaxis.line", title: "Analytics", subtitle: "Volume, strength, consistency")
            }
            NavigationLink(value: Route.muscleMap) {
                ShortcutTile(symbol: "figure.arms.open", title: "Muscle map", subtitle: "What you've trained")
            }
        }
        .buttonStyle(PressableStyle())
    }
}

struct ShortcutTile: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBubble(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.primeHeadline).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .primeCard(padding: 14)
    }
}

// MARK: - Get started

struct GetStartedCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first week starts here").font(.primeTitle).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Plan your week", "Pick a starter split or build your own routines.")
                step(2, "Log every set", "PRIME remembers what you lifted last time.")
                step(3, "Climb the ranks", "Each lift earns its own tier, from Beginner to Elite.")
            }
            HStack(spacing: 10) {
                Button("Build my plan") { appState.showFirstWorkoutGuide = true }
                    .buttonStyle(.primePrimary)
                Button("Quick start") { appState.startWorkout(plan: nil, context: context, store: store) }
                    .buttonStyle(.primeSecondary)
            }
        }
        .primeCard(padding: 18)
        .overlay(alignment: .topTrailing) {
            PrimeMark().fill(Theme.accent.opacity(0.08)).frame(width: 120, height: 120).offset(x: 20, y: -10).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Today

struct TodayCard: View {
    let days: [WorkoutDay]
    let unit: WeightUnit
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store

    private var today: WorkoutDay? { ScheduleService.today(in: days) }
    private var doneToday: SessionSummary? {
        store.history.sessions.first { Calendar.prime.isDateInToday($0.startedAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today").eyebrow()
                Spacer()
                if let next = ScheduleService.nextTrainingDay(in: days), let plan = next.day.plan {
                    Text("Next: \(plan.name) · \(Weekday.shortNames[next.day.weekday])")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            content
        }
        .primeCard(padding: 18)
    }

    @ViewBuilder
    private var content: some View {
        if let active = appState.activeSession {
            todayRow(title: active.name, detail: "In progress · \(active.completedSets.count) sets done", symbol: "bolt.fill")
            Button("Resume workout") { appState.isWorkoutPresented = true }
                .buttonStyle(.primePrimary)
        } else if let done = doneToday {
            todayRow(title: done.name, detail: "Done · \(Format.duration(done.duration)) · \(Format.volume(done.volume, unit: unit))", symbol: "checkmark")
            if let plan = today?.plan, today?.state == .training, done.name != plan.name {
                Button("Start \(plan.name) too") { appState.startWorkout(plan: plan, context: context, store: store) }
                    .buttonStyle(.primeSecondary)
            }
        } else if let day = today, day.state == .training, let plan = day.plan {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.planColor(plan.colorIndex)).frame(width: 10, height: 10)
                    Text(plan.name).font(.primeTitle).foregroundStyle(.white)
                }
                Text("\(plan.entries.count) exercises · \(plan.totalSets) sets · ~\(plan.estimatedMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if !plan.muscles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(plan.muscles) { Tag(text: $0.shortName, color: Theme.accent) } }
                    }
                }
            }
            Button {
                appState.startWorkout(plan: plan, context: context, store: store)
            } label: {
                Label("Start workout", systemImage: "play.fill")
            }
            .buttonStyle(.primePrimary)
        } else if today?.state == .rest {
            todayRow(title: "Rest day", detail: "Recovery is when the strength gets built.", symbol: "moon.zzz.fill")
            Button("Train anyway") { appState.startWorkout(plan: nil, context: context, store: store) }
                .buttonStyle(.primeSecondary)
        } else {
            todayRow(title: "Nothing planned", detail: "Start an empty workout or plan your week.", symbol: "calendar.badge.plus")
            HStack(spacing: 10) {
                Button("Quick start") { appState.startWorkout(plan: nil, context: context, store: store) }
                    .buttonStyle(.primePrimary)
                Button("Plan week") { appState.selectedTab = .workouts }
                    .buttonStyle(.primeSecondary)
            }
        }
    }

    private func todayRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            IconBubble(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.primeTitle).foregroundStyle(.white).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Week progress

struct WeekProgressCard: View {
    let days: [WorkoutDay]
    let weeklyGoal: Int
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let calendar = Calendar.prime
        let weekStart = calendar.startOfWeek(for: Date())
        let trained = Analytics.trainedDays(store.history.sessions)
        let todayIndex = Weekday.index(of: Date())
        let completedCount = store.history.sessions.filter { $0.startedAt >= weekStart }.count
        let planned = days.filter { $0.state == .training }.count
        let target = planned > 0 ? planned : max(1, weeklyGoal)

        return HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: Double(completedCount) / Double(target), lineWidth: 7)
                VStack(spacing: 0) {
                    Text("\(completedCount)").font(.primeNumber(22)).foregroundStyle(.white)
                    Text("of \(target)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 66, height: 66)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(completedCount) of \(target) workouts this week")

            VStack(alignment: .leading, spacing: 10) {
                Text("This week").eyebrow()
                HStack(spacing: 0) {
                    ForEach(Weekday.all, id: \.self) { index in
                        let date = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
                        let done = trained.contains(calendar.startOfDay(for: date))
                        let state = days.first { $0.weekday == index }?.state ?? .unplanned
                        VStack(spacing: 6) {
                            Text(Weekday.initials[index])
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(index == todayIndex ? Theme.accent : Theme.textTertiary)
                            DayDot(done: done, state: state, isToday: index == todayIndex, isPast: index < todayIndex)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(Weekday.longNames[index]): \(done ? "trained" : state == .rest ? "rest day" : state == .training ? "planned" : "nothing planned")")
                    }
                }
            }
        }
        .primeCard()
    }
}

struct DayDot: View {
    let done: Bool
    let state: WorkoutDay.State
    let isToday: Bool
    let isPast: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.onAccent)
            } else {
                switch state {
                case .training:
                    Circle().strokeBorder(isPast ? Theme.danger.opacity(0.6) : Theme.accent.opacity(0.7), lineWidth: 2)
                case .rest:
                    Capsule().fill(Theme.textTertiary).frame(width: 10, height: 3)
                case .unplanned:
                    Circle().fill(Theme.field).frame(width: 8, height: 8)
                }
            }
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().strokeBorder(isToday ? Color.white.opacity(0.5) : .clear, lineWidth: 1).padding(-3))
    }
}

// MARK: - Weekly volume

struct WeeklyVolumeCard: View {
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let calendar = Calendar.prime
        let thisWeek = Analytics.dailyVolume(store.history.samples, weekContaining: Date())
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        let lastWeek = Analytics.dailyVolume(store.history.samples, weekContaining: lastWeekDate)
        let total = thisWeek.reduce(0, +)
        let todayIndex = Weekday.index(of: Date())
        let lastToDate = lastWeek.prefix(todayIndex + 1).reduce(0, +)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly volume").eyebrow()
                    Text(Format.volume(total, unit: unit)).font(.primeNumber(30)).foregroundStyle(.white)
                }
                Spacer()
                if lastToDate > 0 {
                    let change = (total - lastToDate) / lastToDate
                    Tag(text: (change >= 0 ? "▲ " : "▼ ") + Format.percent(abs(change)) + " vs last week",
                        color: change >= 0 ? Theme.accent : Theme.warning)
                }
            }
            Chart {
                ForEach(Weekday.all, id: \.self) { index in
                    BarMark(x: .value("Day", Weekday.shortNames[index]), y: .value("Last week", unit.fromKilograms(lastWeek[index])), width: .ratio(0.55))
                        .foregroundStyle(Theme.field)
                        .position(by: .value("Week", "Last"))
                    BarMark(x: .value("Day", Weekday.shortNames[index]), y: .value("This week", unit.fromKilograms(thisWeek[index])), width: .ratio(0.55))
                        .foregroundStyle(index == todayIndex ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.accent.opacity(0.75)))
                        .position(by: .value("Week", "This"))
                        .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) }
            }
            .frame(height: 140)
            .accessibilityLabel("Volume by day this week compared with last week")
            HStack(spacing: 14) {
                legend(color: Theme.accent, text: "This week")
                legend(color: Theme.field, text: "Last week")
            }
        }
        .primeCard(padding: 18)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Records

struct RecentRecordsCard: View {
    let records: [PersonalRecord]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Recent records")
                NavigationLink(value: Route.records) {
                    Text("See all").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            if records.isEmpty {
                Text("Beat a previous best and it'll show up here. Your first session with a lift sets the baseline.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(records) { record in
                    NavigationLink(value: Route.exercise(record.exerciseSlug)) {
                        RecordRow(record: record, unit: unit)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .primeCard(padding: 18)
    }
}

struct RecordRow: View {
    let record: PersonalRecord
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(symbol: record.kind.symbol, tint: Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(record.kind.displayName) · \(record.achievedAt.relativeDayText)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.valueText(unit: unit)).font(.subheadline.weight(.bold)).foregroundStyle(.white).monospacedDigit()
                if let gain = record.improvementText(unit: unit) {
                    Text(gain).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent performance

struct RecentPerformanceCard: View {
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let slugs = Array(store.history.exerciseSlugsByRecency.prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent lifts")
            ForEach(slugs, id: \.self) { slug in
                NavigationLink(value: Route.exercise(slug)) {
                    row(slug: slug)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .primeCard(padding: 18)
    }

    private func row(slug: String) -> some View {
        let samples = store.history.samples(for: slug)
        let progression = Analytics.oneRepMaxProgression(samples)
        let last = store.history.lastPerformance(for: slug)
        let best = last.max { ($0.estimatedOneRepMax ?? Double($0.reps)) < ($1.estimatedOneRepMax ?? Double($1.reps)) }
        let delta: Double? = progression.count >= 2 ? progression[progression.count - 1].value - progression[progression.count - 2].value : nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.history.exerciseName(for: slug) ?? slug).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(best.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit) } ?? "–")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let e1rm = progression.last?.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.estimate(e1rm, unit: unit)).font(.subheadline.weight(.bold)).foregroundStyle(.white).monospacedDigit()
                    if let delta, abs(delta) > 0.01 {
                        Text((delta > 0 ? "▲ " : "▼ ") + Format.estimate(abs(delta), unit: unit))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delta > 0 ? Theme.accent : Theme.textTertiary)
                    } else {
                        Text("e1RM").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }
}
