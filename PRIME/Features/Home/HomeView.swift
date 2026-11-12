import Charts
import SwiftData
import SwiftUI

/// Sections the user can reorder or hide. Raw values are stored in the profile.
enum DashboardSection: String, CaseIterable, Identifiable {
    case week, quickActions, insights, strength, volume, muscles, recentLifts

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "This week"
        case .quickActions: return "Quick actions"
        case .insights: return "Progress insights"
        case .strength: return "Strength highlights"
        case .volume: return "Training volume"
        case .muscles: return "Muscle distribution"
        case .recentLifts: return "Recent lifts"
        }
    }
    var symbol: String {
        switch self {
        case .week: return "calendar"
        case .quickActions: return "square.grid.2x2"
        case .insights: return "sparkles"
        case .strength: return "trophy"
        case .volume: return "chart.bar"
        case .muscles: return "figure.arms.open"
        case .recentLifts: return "list.bullet"
        }
    }

    static func ordered(order: [String], hidden: [String]) -> [DashboardSection] {
        var result = order.compactMap(DashboardSection.init(rawValue:))
        for section in allCases where !result.contains(section) { result.append(section) }
        return result.filter { !hidden.contains($0.rawValue) }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]

    private var profile: UserProfile? { profiles.first }
    private var unit: WeightUnit { profile?.weightUnit ?? .kg }
    private var history: TrainingHistory { store.history }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HomeHeader(profile: profile, days: days)
                        .appear(0)
                    if history.isEmpty && plans.isEmpty {
                        GetStartedCard().appear(1)
                    }
                    TodayCard(days: days, unit: unit).appear(1)
                    ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                        sectionView(section).appear(index + 2)
                    }
                    NavigationLink(value: Route.dashboardLayout) {
                        Label("Customise dashboard", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .primeBackground()
            .toolbar(.hidden, for: .navigationBar)
            .primeDestinations()
        }
    }

    private var sections: [DashboardSection] {
        DashboardSection.ordered(order: profile?.dashboardOrder ?? [], hidden: profile?.dashboardHidden ?? [])
    }

    @ViewBuilder
    private func sectionView(_ section: DashboardSection) -> some View {
        switch section {
        case .week: WeekActivityCard(days: days, weeklyGoal: profile?.weeklyGoal ?? 3)
        case .quickActions: QuickActionsGrid()
        case .insights: if !history.isEmpty { InsightsCard(days: days, since: profile?.createdAt ?? Date()) }
        case .strength: if !history.isEmpty { StrengthHighlightsCard(unit: unit) }
        case .volume: if !history.isEmpty { WeeklyVolumeCard(unit: unit) }
        case .muscles: if !history.isEmpty { MuscleDistributionCard() }
        case .recentLifts: if !history.isEmpty { RecentPerformanceCard(unit: unit) }
        }
    }
}

// MARK: - Header

struct HomeHeader: View {
    let profile: UserProfile?
    let days: [WorkoutDay]
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let streak = Analytics.weekStreak(sessionDates: store.history.sessions.map(\.startedAt), weeklyGoal: profile?.weeklyGoal ?? 3)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PrimeMark().fill(Theme.accentGradient).frame(width: 22, height: 22)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).eyebrow()
                Spacer()
                Button { appState.showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                }
                .accessibilityLabel("Search")
                Button { appState.selectedTab = .profile } label: {
                    AvatarView(data: profile?.photoData, initials: profile?.initials ?? "", size: 40)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Profile")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(greeting), \(profile?.displayName ?? "Athlete")")
                    .font(.primeLargeTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 8) {
                    if streak > 0 {
                        Tag(text: "\(streak)-week streak", color: Theme.warning, symbol: "flame.fill")
                    }
                    Text(status).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.prime.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var status: String {
        if appState.activeSession != nil { return "Workout in progress" }
        if store.history.sessions.contains(where: { Calendar.prime.isDateInToday($0.startedAt) }) { return "Trained today" }
        guard let today = ScheduleService.today(in: days) else { return "Ready when you are" }
        switch today.state {
        case .training: return "\(today.plan?.name ?? "Workout") planned today"
        case .rest: return "Rest day"
        case .unplanned: return "Nothing planned today"
        }
    }
}

// MARK: - Get started

struct GetStartedCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up your week").font(.primeTitle).foregroundStyle(Theme.textPrimary)
            Text("Pick a proven split and the day you want to start, or build your own routines from 130+ exercises.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            Button { appState.showSplitPresets = true } label: { Label("Choose a training split", systemImage: "square.stack.3d.up") }
                .buttonStyle(.primePrimary)
            HStack(spacing: 10) {
                Button("Build my own") { appState.selectedTab = .workouts }.buttonStyle(.primeSecondary)
                Button("Quick start") { appState.startWorkout(plan: nil, context: context, store: store) }.buttonStyle(.primeSecondary)
            }
        }
        .primeCard(padding: 18, highlight: Theme.accent)
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
                    Text("Next · \(plan.name), \(Weekday.shortNames[next.day.weekday])")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            content
        }
        .primeHero(tint: heroTint)
    }

    private var heroTint: Color {
        if appState.activeSession != nil { return Theme.accentHighlight }
        if doneToday != nil { return Theme.success }
        if let day = today, day.state == .training, let plan = day.plan { return Theme.planColor(plan.colorIndex) }
        return Theme.accent
    }

    @ViewBuilder
    private var content: some View {
        if let active = appState.activeSession {
            row(title: active.name, detail: "In progress · \(active.completedSets.count) sets done", symbol: "bolt.fill")
            Button { appState.isWorkoutPresented = true } label: { Label("Resume workout", systemImage: "play.fill") }
                .buttonStyle(.primePrimary)
        } else if let done = doneToday {
            row(title: done.name, detail: "Done · \(Format.duration(done.duration)) · \(done.setCount) sets", symbol: "checkmark")
            NavigationLink(value: Route.session(done.id)) {
                Text("View workout").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primeSecondary)
        } else if let day = today, day.state == .training, let plan = day.plan {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.planColor(plan.colorIndex)).frame(width: 4, height: 30)
                    Text(plan.name).font(.primeLargeTitle).foregroundStyle(Theme.textPrimary)
                }
                Text("\(plan.entries.count) exercises · \(plan.totalSets) sets · about \(plan.estimatedMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if !plan.muscles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(plan.muscles) { Tag(text: $0.shortName, color: Theme.accentHighlight) } }
                    }
                }
            }
            Button { appState.startWorkout(plan: plan, context: context, store: store) } label: {
                Label("Start \(plan.name)", systemImage: "play.fill")
            }
            .buttonStyle(.primePrimary)
        } else if today?.state == .rest {
            row(title: "Rest day", detail: "Recovery is part of training.", symbol: "moon.zzz.fill")
            Button("Train anyway") { appState.startWorkout(plan: nil, context: context, store: store) }
                .buttonStyle(.primeSecondary)
        } else {
            row(title: "Nothing planned", detail: "Start an empty workout or plan your week.", symbol: "calendar.badge.plus")
            HStack(spacing: 10) {
                Button("Quick start") { appState.startWorkout(plan: nil, context: context, store: store) }
                    .buttonStyle(.primePrimary)
                Button("Plan week") { appState.selectedTab = .workouts }
                    .buttonStyle(.primeSecondary)
            }
        }
    }

    private func row(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            IconBubble(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.primeTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Week activity

struct WeekActivityCard: View {
    let days: [WorkoutDay]
    let weeklyGoal: Int
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let calendar = Calendar.prime
        let weekStart = calendar.startOfWeek(for: Date())
        let trained = Analytics.trainedDays(store.history.sessions)
        let todayIndex = Weekday.index(of: Date())
        let completed = store.history.sessions.filter { $0.startedAt >= weekStart }.count
        let planned = days.filter { $0.state == .training }.count
        let target = planned > 0 ? planned : max(1, weeklyGoal)
        let upcoming = (1...6).compactMap { offset -> (Date, WorkoutDay)? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())),
                  let day = days.first(where: { $0.weekday == Weekday.index(of: date) && $0.state == .training }) else { return nil }
            return (date, day)
        }.prefix(2)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: Double(completed) / Double(target), lineWidth: 7)
                    VStack(spacing: 0) {
                        CountUp(value: Double(completed)) { "\(Int($0.rounded()))" }
                            .font(.primeNumber(22)).foregroundStyle(Theme.textPrimary)
                        Text("of \(target)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 66, height: 66)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(completed) of \(target) workouts this week")
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
                                    .foregroundStyle(index == todayIndex ? Theme.accentHighlight : Theme.textTertiary)
                                DayDot(done: done, state: state, isToday: index == todayIndex, isPast: index < todayIndex, index: index)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(Weekday.longNames[index]): \(done ? "completed" : state == .rest ? "rest day" : state == .training ? (index < todayIndex ? "planned, not logged" : "planned") : "nothing planned")")
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legend(symbol: "checkmark.circle.fill", color: Theme.accent, text: "Done")
                legend(symbol: "circle", color: Theme.accentHighlight, text: "Planned")
                legend(symbol: "minus", color: Theme.textTertiary, text: "Rest")
            }
            if !upcoming.isEmpty {
                DividerLine()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coming up").eyebrow()
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, pair in
                        let (date, day) = pair
                        let color = Theme.planColor(day.plan?.colorIndex ?? 0)
                        HStack(spacing: 10) {
                            Tag(text: Weekday.shortNames[day.weekday], color: color, filled: true)
                            Text(day.plan?.name ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(date.relativeDayText == "Today" ? "Today" : date.relativeDayText == "Tomorrow" ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide)))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .primeCard()
    }

    private func legend(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color)
            Text(text).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct DayDot: View {
    let done: Bool
    let state: WorkoutDay.State
    let isToday: Bool
    let isPast: Bool
    var index: Int = 0
    @Environment(\.motion) private var motion
    @State private var shown = false

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.accentGradient)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                    .scaleEffect(shown || !motion.allowsMovement ? 1 : 0.2)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.onAccent)
                    .opacity(shown || !motion.allowsAnimation ? 1 : 0)
            } else {
                switch state {
                case .training:
                    Circle()
                        .trim(from: 0, to: shown || !motion.allowsAnimation ? 1 : 0)
                        .stroke(isPast ? Theme.danger.opacity(0.55) : Theme.accentHighlight.opacity(0.85),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: isPast ? [3, 3] : []))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                case .rest:
                    Capsule().fill(Theme.textTertiary).frame(width: 10, height: 3)
                case .unplanned:
                    Circle().fill(Theme.field).frame(width: 7, height: 7)
                }
            }
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().strokeBorder(isToday ? Color.white.opacity(0.45) : .clear, lineWidth: 1).padding(-3))
        .onAppear {
            withAnimation(motion.animation(.spring(response: 0.5, dampingFraction: 0.6)).map { $0.delay(0.25 + Double(index) * 0.06) }) { shown = true }
        }
    }
}

// MARK: - Quick actions

struct QuickActionsGrid: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(TrainingStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick actions").eyebrow()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                action("play.fill", "Start", "workout") { appState.startWorkout(plan: nil, context: context, store: store) }
                action("shield.lefthalf.filled", "Log", "ranked lift") { appState.rankEntry = RankEntryRequest(exerciseSlug: nil) }
                action("dumbbell.fill", "Browse", "exercises") { appState.selectedTab = .exercises }
                action("chart.bar.fill", "View", "rankings") { appState.selectedTab = .rankings }
                action("square.stack.3d.up.fill", "Plan", "my week") { appState.showSplitPresets = true }
                NavigationLink(value: Route.analytics) { tile("chart.xyaxis.line", "Open", "analytics") }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    private func action(_ symbol: String, _ verb: String, _ noun: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { tile(symbol, verb, noun) }.buttonStyle(PressableStyle())
    }

    private func tile(_ symbol: String, _ verb: String, _ noun: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentHighlight)
            VStack(alignment: .leading, spacing: 0) {
                Text(verb).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(noun).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Insights

struct InsightsCard: View {
    let days: [WorkoutDay]
    let since: Date
    @Environment(TrainingStore.self) private var store
    @State private var expanded = false

    var body: some View {
        let planned = Set(days.filter { $0.state == .training }.map(\.weekday))
        let insights = InsightEngine.all(history: store.history, plannedWeekdays: planned, trackingSince: since,
                                         timedSlugs: ExerciseLibrary.shared.timedSlugs)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Progress insights", subtitle: "From your logged workouts")
            if insights.isEmpty {
                Text("Keep logging. Observations appear once there are a few sessions to compare.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(insights.prefix(expanded ? 8 : 3))) { insight in
                InsightRow(insight: insight)
            }
            if insights.count > 3 {
                Button(expanded ? "Show fewer" : "Show \(min(8, insights.count) - 3) more") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentHighlight)
            }
        }
        .primeCard(padding: 18)
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        let content = HStack(alignment: .top, spacing: 12) {
            IconBubble(symbol: insight.symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion = insight.suggestion {
                    Label(suggestion, systemImage: "lightbulb")
                        .font(.caption).foregroundStyle(Theme.accentHighlight)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let slug = insight.exerciseSlug {
            NavigationLink(value: Route.exercise(slug)) { content }.buttonStyle(PressableStyle())
        } else if let muscle = insight.muscle {
            NavigationLink(value: Route.muscle(muscle)) { content }.buttonStyle(PressableStyle())
        } else {
            content
        }
    }

    private var tint: Color {
        switch insight.tone {
        case .positive: return Theme.success
        case .neutral: return Theme.accentHighlight
        case .attention: return Theme.warning
        }
    }
}

// MARK: - Strength highlights

struct StrengthHighlightsCard: View {
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query(sort: \PerformanceRanking.recordedAt) private var rankings: [PerformanceRanking]

    var body: some View {
        let improved = InsightEngine.mostImproved(history: store.history).prefix(3)
        let rankUps = RankingService.rankUps(rankings).prefix(3)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "Strength highlights")
                NavigationLink(value: Route.records) {
                    Text("Records").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                }
            }
            if records.isEmpty && improved.isEmpty && rankUps.isEmpty {
                Text("Your first session with a lift sets its baseline. Beat it next time and highlights appear here.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent records").eyebrow()
                    ForEach(records.prefix(3)) { record in
                        NavigationLink(value: Route.exercise(record.exerciseSlug)) { RecordRow(record: record, unit: unit) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
            if !improved.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Most improved · 60 days").eyebrow()
                    ForEach(Array(improved)) { item in
                        NavigationLink(value: Route.exercise(item.slug)) {
                            HStack {
                                Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Text("+" + Format.percent(item.change)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.success)
                                Text(item.isOneRepMax ? "e1RM" : "reps").font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            if !rankUps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rank achievements").eyebrow()
                    ForEach(Array(rankUps)) { entry in
                        NavigationLink(value: Route.exerciseRank(entry.exerciseSlug)) {
                            HStack(spacing: 10) {
                                RankEmblem(tier: entry.tier, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    Text("Reached \(entry.tier.name) · \(entry.recordedAt.relativeDayText)").font(.caption).foregroundStyle(entry.tier.color)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
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
            IconBubble(symbol: record.kind.symbol, tint: Theme.warning, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(record.kind.displayName) · \(record.achievedAt.relativeDayText)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.valueText(unit: unit)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                if let gain = record.improvementText(unit: unit) {
                    Text(gain).font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Weekly volume

struct WeeklyVolumeCard: View {
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store
    @Environment(\.motion) private var motion
    @State private var grown = false

    var body: some View {
        let calendar = Calendar.prime
        let thisWeek = Analytics.dailyVolume(store.history.samples, weekContaining: Date())
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        let lastWeek = Analytics.dailyVolume(store.history.samples, weekContaining: lastWeekDate)
        let total = thisWeek.reduce(0, +)
        let todayIndex = Weekday.index(of: Date())
        let lastToDate = lastWeek.prefix(todayIndex + 1).reduce(0, +)
        let weekStart = calendar.startOfWeek(for: Date())
        let lastStart = calendar.startOfWeek(for: lastWeekDate)
        let sessionsThis = store.history.sessions.filter { $0.startedAt >= weekStart }.count
        let sessionsLast = store.history.sessions.filter { $0.startedAt >= lastStart && $0.startedAt < weekStart }.count
        let scale = grown || !motion.allowsAnimation ? 1.0 : 0.0

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training volume").eyebrow()
                    CountUp(value: unit.fromKilograms(total)) { Format.number($0.rounded(), maxFractionDigits: 0) + " \(unit.symbol)" }
                        .font(.primeNumber(30)).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if lastToDate > 0 {
                    let change = (total - lastToDate) / lastToDate
                    Tag(text: (change >= 0 ? "▲ " : "▼ ") + Format.percent(abs(change)) + " vs same point last week",
                        color: change >= 0 ? Theme.success : Theme.textSecondary)
                }
            }
            Chart {
                ForEach(Weekday.all, id: \.self) { index in
                    BarMark(x: .value("Day", Weekday.shortNames[index]), y: .value("Volume", unit.fromKilograms(lastWeek[index]) * scale), width: .ratio(0.5))
                        .foregroundStyle(Theme.field)
                        .position(by: .value("Week", "Last"))
                        .cornerRadius(3)
                    BarMark(x: .value("Day", Weekday.shortNames[index]), y: .value("Volume", unit.fromKilograms(thisWeek[index]) * scale), width: .ratio(0.5))
                        .foregroundStyle(index <= todayIndex ? AnyShapeStyle(Theme.barGradient) : AnyShapeStyle(Theme.barGradientDim))
                        .position(by: .value("Week", "This"))
                        .cornerRadius(3)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .frame(height: 140)
            .onAppear { withAnimation(motion.animation(.spring(response: 0.8, dampingFraction: 0.85))) { grown = true } }
            .accessibilityLabel("Volume by day this week compared with last week")
            HStack(spacing: 14) {
                legend(color: Theme.accent, text: "This week · \(sessionsThis) workout\(sessionsThis == 1 ? "" : "s")")
                legend(color: Theme.field, text: "Last week · \(sessionsLast)")
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

// MARK: - Muscle distribution

struct MuscleDistributionCard: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.bodyModel) private var model

    private static func ranking(_ a: MuscleScore, _ b: MuscleScore) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.muscle.displayName < b.muscle.displayName
    }

    var body: some View {
        let start = Calendar.prime.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let samples = store.history.samples(in: DateInterval(start: start, end: Date()))
        let sets = Analytics.setsByMuscle(samples)
        let scores: [MuscleScore] = sets.map { MuscleScore(muscle: $0.key, score: Double($0.value)) }
        let top: [MuscleScore] = Array(scores.sorted(by: Self.ranking).prefix(5))
        let maxSets: Double = max(1, top.first?.score ?? 1)
        let heat = sets.mapValues { min(1, Double($0) / 10) }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Muscle distribution", subtitle: "Working sets, last 7 days")
                NavigationLink(value: Route.muscleMap) {
                    Text("Explore").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                }
            }
            if top.isEmpty {
                Text("No sets in the last 7 days.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    HStack(spacing: 2) {
                        AnatomyCanvas(side: .front, heat: heat, model: model).frame(width: 56, height: 120)
                        AnatomyCanvas(side: .back, heat: heat, model: model).frame(width: 56, height: 120)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(top) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.muscle.displayName).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(Int(row.score))").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                                ProgressBar(progress: row.score / maxSets, height: 4)
                            }
                        }
                    }
                }
            }
        }
        .primeCard(padding: 18)
    }
}

// MARK: - Recent lifts

struct RecentPerformanceCard: View {
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let slugs = Array(store.history.exerciseSlugsByRecency.prefix(4))
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent lifts")
            ForEach(slugs, id: \.self) { slug in
                NavigationLink(value: Route.exercise(slug)) { row(slug: slug) }
                    .buttonStyle(PressableStyle())
            }
        }
        .primeCard(padding: 18)
    }

    private func row(slug: String) -> some View {
        let samples = store.history.samples(for: slug)
        let timed = samples.first?.isTimed ?? false
        let progression = Analytics.oneRepMaxProgression(samples)
        let last = store.history.lastPerformance(for: slug)
        let best = last.max { ($0.estimatedOneRepMax ?? Double($0.reps)) < ($1.estimatedOneRepMax ?? Double($1.reps)) }
        let delta: Double? = progression.count >= 2 ? progression[progression.count - 1].value - progression[progression.count - 2].value : nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.history.exerciseName(for: slug) ?? slug).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(best.map { Format.set(weightKg: $0.weightKg, reps: $0.reps, unit: unit, timed: timed) } ?? "–")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let e1rm = progression.last?.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.estimate(e1rm, unit: unit)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    if let delta, abs(delta) > 0.01 {
                        Text((delta > 0 ? "▲ " : "▼ ") + Format.estimate(abs(delta), unit: unit))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delta > 0 ? Theme.success : Theme.textTertiary)
                    } else {
                        Text("est. 1RM").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }
}
