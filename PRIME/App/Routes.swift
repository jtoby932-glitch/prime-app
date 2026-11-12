import SwiftData
import SwiftUI

/// Every pushable screen. Each tab's NavigationStack registers these once.
enum Route: Hashable {
    case analytics
    case muscleMap
    case muscle(MuscleGroup)
    case category(MuscleGroup)
    case allExercises
    case equipment(Equipment)
    case favourites
    case records
    case achievements
    case bodyweight
    case notifications
    case preferences
    case dashboardLayout
    case methodology
    case licences
    case rankHistory
    case exercise(String)
    case exerciseRank(String)
    case exerciseHistory(String)
    case session(UUID)
    case plan(UUID)
}

extension Route: Identifiable {
    var id: Self { self }
}

extension View {
    func primeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route)
        }
    }
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .analytics: AnalyticsView()
        case .muscleMap: MuscleMapView()
        case .muscle(let muscle): MuscleMapView(initial: muscle)
        case .category(let muscle): ExerciseCategoryView(scope: .muscle(muscle))
        case .allExercises: ExerciseCategoryView(scope: .all)
        case .equipment(let item): ExerciseCategoryView(scope: .equipment(item))
        case .favourites: ExerciseCategoryView(scope: .favourites)
        case .records: PersonalRecordsView()
        case .achievements: AchievementsView()
        case .bodyweight: BodyweightView()
        case .notifications: NotificationSettingsView()
        case .preferences: PreferencesView()
        case .dashboardLayout: DashboardLayoutView()
        case .methodology: RankingMethodologyView()
        case .licences: LicencesView()
        case .rankHistory: RankHistoryView()
        case .exercise(let slug): ExerciseLoader(slug: slug) { ExerciseDetailView(exercise: $0) }
        case .exerciseRank(let slug): ExerciseLoader(slug: slug) { ExerciseRankDetailView(exercise: $0) }
        case .exerciseHistory(let slug): ExerciseLoader(slug: slug) { ExerciseHistoryView(exercise: $0) }
        case .session(let id): SessionLoader(id: id) { SessionDetailView(session: $0) }
        case .plan(let id): PlanLoader(id: id) { PlanDetailView(plan: $0) }
        }
    }
}

struct ExerciseLoader<Content: View>: View {
    @Query private var matches: [Exercise]
    private let content: (Exercise) -> Content

    init(slug: String, @ViewBuilder content: @escaping (Exercise) -> Content) {
        _matches = Query(filter: #Predicate<Exercise> { $0.slug == slug })
        self.content = content
    }

    var body: some View {
        if let exercise = matches.first {
            content(exercise)
        } else {
            MissingItemView(title: "Exercise not found", message: "It may have been deleted. Your logged history for it is still kept.")
        }
    }
}

struct SessionLoader<Content: View>: View {
    @Query private var matches: [WorkoutSession]
    private let content: (WorkoutSession) -> Content

    init(id: UUID, @ViewBuilder content: @escaping (WorkoutSession) -> Content) {
        _matches = Query(filter: #Predicate<WorkoutSession> { $0.uuid == id })
        self.content = content
    }

    var body: some View {
        if let session = matches.first {
            content(session)
        } else {
            MissingItemView(title: "Workout not found", message: "This workout was deleted.")
        }
    }
}

struct PlanLoader<Content: View>: View {
    @Query private var matches: [WorkoutPlan]
    private let content: (WorkoutPlan) -> Content

    init(id: UUID, @ViewBuilder content: @escaping (WorkoutPlan) -> Content) {
        _matches = Query(filter: #Predicate<WorkoutPlan> { $0.uuid == id })
        self.content = content
    }

    var body: some View {
        if let plan = matches.first {
            content(plan)
        } else {
            MissingItemView(title: "Routine not found", message: "This routine was deleted.")
        }
    }
}

struct MissingItemView: View {
    let title: String
    let message: String

    var body: some View {
        EmptyStateView(symbol: "questionmark.folder", title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .primeBackground()
    }
}
