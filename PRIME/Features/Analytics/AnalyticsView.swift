import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Environment(TrainingStore.self) private var store
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutDay.weekday) private var days: [WorkoutDay]
    @State private var range: AnalyticsRange = .quarter
    @State private var useCustom = false
    @State private var customStart = Calendar.prime.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var customEnd = Date()

    private var unit: WeightUnit { profiles.first?.weightUnit ?? .kg }
    private var history: TrainingHistory { store.history }

    private var interval: DateInterval {
        if useCustom {
            let start = Calendar.prime.startOfDay(for: min(customStart, customEnd))
            let end = Calendar.prime.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.prime.startOfDay(for: max(customStart, customEnd))) ?? customEnd
            return DateInterval(start: start, end: max(start, end))
        }
        return range.interval(earliest: history.firstSessionDate)
    }

    private var bucket: BucketSize {
        if useCustom { return interval.duration > 200 * 86_400 ? .month : .week }
        return range.preferredBucket
    }

    var body: some View {
        let samples = history.samples(in: interval)
        let sessions = history.sessions(in: interval)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                rangePicker
                if history.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line", title: "Nothing to analyse yet",
                                   message: "Finish a workout and your volume, strength and consistency charts will build from real data.")
                        .primeCard()
                } else {
                    summaryTiles(samples: samples, sessions: sessions)
                    VolumeOverTimeCard(samples: samples, interval: interval, bucket: bucket, unit: unit)
                    MuscleVolumeCard(samples: samples, unit: unit)
                    ExerciseVolumeCard(samples: samples, unit: unit)
                    StrengthProgressCard(interval: interval, unit: unit)
                    ConsistencyCard(sessions: sessions, interval: interval, bucket: bucket, plannedPerWeek: days.filter { $0.state == .training }.count,
                                    weeklyGoal: profiles.first?.weeklyGoal ?? 3)
                    CalendarHistoryCard()
                    NavigationLink(value: Route.records) {
                        HStack {
                            Label("All personal records", systemImage: "trophy.fill").font(.headline).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                        }
                        .primeCard()
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .primeBackground()
        .navigationTitle("Analytics")
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AnalyticsRange.allCases) { option in
                        Chip(title: option.label, isSelected: !useCustom && range == option) {
                            useCustom = false
                            range = option
                        }
                    }
                    Chip(title: "Custom", symbol: "calendar", isSelected: useCustom) { useCustom.toggle() }
                }
            }
            if useCustom {
                HStack {
                    DatePicker("From", selection: $customStart, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Text("to").foregroundStyle(Theme.textSecondary)
                    DatePicker("To", selection: $customEnd, in: ...Date(), displayedComponents: .date).labelsHidden()
                }
            }
            Text(interval.start.formatted(date: .abbreviated, time: .omitted) + " – " + interval.end.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func summaryTiles(samples: [SetSample], sessions: [SessionSummary]) -> some View {
        let average = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: "\(sessions.count)", label: "Workouts", symbol: "checkmark.seal.fill")
            StatTile(value: Format.volume(Analytics.totalVolume(samples), unit: unit, includeUnit: false), label: "Volume (\(unit.symbol))", symbol: "scalemass.fill", tint: Theme.info)
            StatTile(value: "\(samples.count)", label: "Working sets", symbol: "square.stack.3d.up.fill", tint: Theme.warning)
            StatTile(value: sessions.isEmpty ? "–" : Format.duration(average), label: "Avg. duration", symbol: "clock.fill")
        }
    }
}

// MARK: - Volume over time

struct VolumeOverTimeCard: View {
    let samples: [SetSample]
    let interval: DateInterval
    let bucket: BucketSize
    let unit: WeightUnit
    @State private var selected: Date?

    var body: some View {
        let buckets = Analytics.volume(samples, by: bucket, in: interval)
        let selectedBucket = selected.flatMap { date in buckets.last { $0.start <= date } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bucket.displayName) volume").eyebrow()
                    Text(selectedBucket.map { Format.volume($0.value, unit: unit) } ?? Format.volume(Analytics.totalVolume(samples), unit: unit))
                        .font(.primeNumber(26)).foregroundStyle(.white)
                    Text(selectedBucket.map { label(for: $0.start) } ?? "Total in range")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            Chart {
                ForEach(buckets) { item in
                    BarMark(x: .value("Period", item.start, unit: bucket == .week ? .weekOfYear : .month),
                            y: .value("Volume", unit.fromKilograms(item.value)))
                        .foregroundStyle(selectedBucket?.start == item.start ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accentGradient))
                        .cornerRadius(3)
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: axisFormat).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 180)
            .accessibilityLabel("\(bucket.displayName) training volume")
            Text("Drag across the chart to inspect a \(bucket == .week ? "week" : "month"). Volume is weight × reps of working sets.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 18)
    }

    private var axisFormat: Date.FormatStyle {
        bucket == .week ? Date.FormatStyle().day().month(.abbreviated) : Date.FormatStyle().month(.abbreviated)
    }

    private func label(for date: Date) -> String {
        bucket == .week ? "Week of " + date.formatted(.dateTime.day().month(.abbreviated)) : date.formatted(.dateTime.month(.wide).year())
    }
}

// MARK: - By muscle

struct MuscleVolumeCard: View {
    let samples: [SetSample]
    let unit: WeightUnit
    @State private var showSets = false

    var body: some View {
        let volume = Analytics.volumeByMuscle(samples)
        let sets = Analytics.setsByMuscle(samples)
        let rows = MuscleGroup.allCases
            .map { MuscleScore(muscle: $0, score: showSets ? Double(sets[$0] ?? 0) : unit.fromKilograms(volume[$0] ?? 0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "By muscle group")
                Picker("Measure", selection: $showSets) {
                    Text("Volume").tag(false)
                    Text("Sets").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            if rows.isEmpty {
                Text("No working sets in this range.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                Chart(rows) { row in
                    BarMark(x: .value(showSets ? "Sets" : "Volume", row.score), y: .value("Muscle", row.muscle.displayName))
                        .foregroundStyle(Theme.accent.opacity(0.35 + 0.65 * row.score / (rows.first?.score ?? 1)))
                        .cornerRadius(3)
                        .annotation(position: .trailing) {
                            Text(showSets ? "\(Int(row.score))" : Format.number(row.score, maxFractionDigits: 0))
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                .frame(height: CGFloat(rows.count) * 28 + 10)
            }
            Text(showSets ? "Working sets that list the muscle as a primary target." : "Weight × reps credited to each exercise's primary muscles (\(unit.symbol)). Bodyweight sets add reps, not volume — switch to Sets to see them.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 18)
    }
}

// MARK: - By exercise

struct ExerciseVolumeCard: View {
    let samples: [SetSample]
    let unit: WeightUnit

    var body: some View {
        let rows = Array(Analytics.volumeByExercise(samples).prefix(8))
        let top = rows.first?.volume ?? 1
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By exercise")
            if rows.isEmpty {
                Text("No loaded sets in this range.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            ForEach(rows) { row in
                NavigationLink(value: Route.exercise(row.slug)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(Format.volume(row.volume, unit: unit)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        ProgressBar(progress: row.volume / top, tint: AnyShapeStyle(Theme.accentGradient), height: 5)
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .primeCard(padding: 18)
    }
}

// MARK: - Strength progression

struct StrengthProgressCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case oneRepMax = "e1RM", weight = "Heaviest", reps = "Reps", volume = "Volume"
        var id: String { rawValue }
    }

    let interval: DateInterval
    let unit: WeightUnit
    @Environment(TrainingStore.self) private var store
    @State private var slug: String?
    @State private var metric: Metric = .oneRepMax
    @State private var selected: Date?

    var body: some View {
        let options = store.history.exerciseSlugsByRecency
        let active = slug.flatMap { options.contains($0) ? $0 : nil } ?? options.first
        let samples = active.map { store.history.samples(for: $0, in: interval) } ?? []
        let isBodyweight = !samples.isEmpty && samples.allSatisfy { $0.weightKg == 0 }
        let effectiveMetric: Metric = isBodyweight && metric != .reps ? .reps : metric
        let points: [ExercisePoint] = {
            switch effectiveMetric {
            case .oneRepMax: return Analytics.oneRepMaxProgression(samples)
            case .weight: return Analytics.weightProgression(samples)
            case .reps: return Analytics.repProgression(samples)
            case .volume: return Analytics.sessionVolumeProgression(samples)
            }
        }()
        let isWeight = effectiveMetric != .reps
        let display: (Double) -> String = { value in
            switch effectiveMetric {
            case .oneRepMax: return Format.estimate(value, unit: unit)
            case .volume: return Format.volume(value, unit: unit)
            case .weight: return Format.weight(value, unit: unit)
            case .reps: return "\(Int(value)) reps"
            }
        }
        let plotted = points.map { isWeight ? unit.fromKilograms($0.value) : $0.value }
        let floor = (plotted.min() ?? 0) * 0.9
        let ceiling = max(floor + 1, (plotted.max() ?? 1) * 1.05)
        let selectedPoint = selected.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        let best = points.max { $0.value < $1.value }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Strength progression")
            }
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(store.history.exerciseName(for: option) ?? option) { slug = option }
                }
            } label: {
                HStack {
                    Text(active.flatMap { store.history.exerciseName(for: $0) } ?? "Choose exercise").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
            }
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                Text("No sessions with this exercise in the selected range.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(display(selectedPoint?.value ?? points.last?.value ?? 0)).font(.primeNumber(26)).foregroundStyle(.white)
                    Text(selectedPoint.map { $0.date.relativeDayText } ?? "Latest").font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let first = points.first?.value, let last = points.last?.value, first > 0, points.count > 1 {
                        let change = (last - first) / first
                        Tag(text: (change >= 0 ? "+" : "") + Format.percent(change), color: change >= 0 ? Theme.accent : Theme.warning)
                    }
                }
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Value", isWeight ? unit.fromKilograms(point.value) : point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        AreaMark(x: .value("Date", point.date), yStart: .value("Floor", floor), yEnd: .value("Value", isWeight ? unit.fromKilograms(point.value) : point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                        PointMark(x: .value("Date", point.date), y: .value("Value", isWeight ? unit.fromKilograms(point.value) : point.value))
                            .foregroundStyle(point.sessionID == best?.sessionID ? Theme.warning : Theme.accent)
                            .symbolSize(point.sessionID == best?.sessionID ? 60 : 20)
                    }
                    if let selectedPoint {
                        RuleMark(x: .value("Selected", selectedPoint.date)).foregroundStyle(Theme.strokeStrong)
                    }
                }
                .chartYScale(domain: floor...ceiling)
                .chartXSelection(value: $selected)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 200)
                Text(caption(effectiveMetric)).font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .primeCard(padding: 18)
    }

    private func caption(_ metric: Metric) -> String {
        switch metric {
        case .oneRepMax: return "Best estimated 1RM per workout (Epley; sets above 12 reps aren't counted as reliable). Orange marks your best."
        case .weight: return "Heaviest weight lifted per workout."
        case .reps: return "Most reps in one set per workout."
        case .volume: return "Total volume for this exercise per workout."
        }
    }
}

// MARK: - Consistency

struct ConsistencyCard: View {
    let sessions: [SessionSummary]
    let interval: DateInterval
    let bucket: BucketSize
    let plannedPerWeek: Int
    let weeklyGoal: Int
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let weekly = Analytics.frequency(sessions, by: .week, in: interval)
        let target = plannedPerWeek > 0 ? plannedPerWeek : max(1, weeklyGoal)
        let completedWeeks = weekly.filter { $0.value >= Double(target) }.count
        let allDates = store.history.sessions.map(\.startedAt)
        let streak = Analytics.weekStreak(sessionDates: allDates, weeklyGoal: weeklyGoal)
        let best = Analytics.bestWeekStreak(sessionDates: allDates, weeklyGoal: weeklyGoal)
        let average = weekly.isEmpty ? 0 : weekly.reduce(0) { $0 + $1.value } / Double(weekly.count)

        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Consistency")
            HStack(spacing: 10) {
                miniStat("\(streak)", "Current streak")
                miniStat("\(best)", "Best streak")
                miniStat(Format.number(average, maxFractionDigits: 1), "Per week")
            }
            Chart {
                ForEach(weekly) { item in
                    BarMark(x: .value("Week", item.start, unit: .weekOfYear), y: .value("Workouts", item.value))
                        .foregroundStyle(item.value >= Double(target) ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.35)))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.warning.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(target)").font(.caption2).foregroundStyle(Theme.warning)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 150)
            Text("You hit your weekly target in \(completedWeeks) of \(weekly.count) weeks in this range. A streak counts consecutive weeks with at least \(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s").")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .primeCard(padding: 18)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.primeNumber(22)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }
}

// MARK: - Calendar

struct CalendarHistoryCard: View {
    @Environment(TrainingStore.self) private var store
    @State private var month = Calendar.prime.startOfMonth(for: Date())

    var body: some View {
        let calendar = Calendar.prime
        let trained = Analytics.trainedDays(store.history.sessions)
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = Weekday.index(of: month, calendar: calendar)
        let count = (0..<daysInMonth).filter { offset in
            calendar.date(byAdding: .day, value: offset, to: month).map { trained.contains(calendar.startOfDay(for: $0)) } ?? false
        }.count

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                VStack(spacing: 2) {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(.white)
                    Text("\(count) training day\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { Text(Weekday.initials[$0]).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary) }
                ForEach(0..<(leading + daysInMonth), id: \.self) { cell in
                    if cell < leading {
                        Color.clear.frame(height: 34)
                    } else {
                        let date = calendar.date(byAdding: .day, value: cell - leading, to: month) ?? month
                        let done = trained.contains(calendar.startOfDay(for: date))
                        let isToday = calendar.isDateInToday(date)
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption.weight(done ? .heavy : .medium).monospacedDigit())
                            .foregroundStyle(done ? Theme.onAccent : (date > Date() ? Theme.textTertiary : Theme.textSecondary))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(done ? Theme.accent : Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isToday ? .white.opacity(0.6) : .clear, lineWidth: 1))
                            .accessibilityLabel(date.formatted(date: .long, time: .omitted) + (done ? ", trained" : ""))
                    }
                }
            }
        }
        .primeCard(padding: 18)
    }

    private func shift(_ months: Int) {
        if let next = Calendar.prime.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }
}
