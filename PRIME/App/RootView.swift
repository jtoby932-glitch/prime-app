import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @State private var isReady = false
    @State private var setupError: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !isReady {
                LaunchView(error: setupError)
            } else if profiles.first?.hasCompletedOnboarding == true {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isReady)
        .animation(.easeInOut(duration: 0.35), value: profiles.first?.hasCompletedOnboarding)
        .task { prepare() }
        .onChange(of: scenePhase) { _, phase in
            guard isReady, phase == .active else { return }
            store.refresh(context)
            appState.refreshNotifications(context: context, history: store.history)
        }
    }

    private func prepare() {
        guard !isReady else { return }
        do {
            try CatalogueService.seedIfNeeded(context: context)
        } catch {
            setupError = "The exercise library couldn't load: \(error.localizedDescription)"
        }
        ScheduleService.ensureWeek(context: context)
        _ = DataService.profile(in: context)
        store.refresh(context)
        appState.restoreActiveSession(context: context)
        #if DEBUG
        DemoData.apply(context: context, store: store, appState: appState)
        #endif
        appState.refreshNotifications(context: context, history: store.history)
        isReady = true
    }
}

struct LaunchView: View {
    var error: String?

    var body: some View {
        VStack(spacing: 18) {
            PrimeWordmark(size: 44)
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

struct PrimeWordmark: View {
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: size * 0.18) {
            PrimeMark()
                .fill(Theme.accentGradient)
                .frame(width: size * 0.9, height: size * 0.9)
            Text("PRIME")
                .font(.system(size: size, weight: .black).width(.condensed))
                .tracking(size * 0.06)
                .foregroundStyle(.white)
        }
        .accessibilityElement()
        .accessibilityLabel("PRIME")
    }
}

/// The PRIME mark: a rising peak cut from a square.
struct PrimeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.74, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.5))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.26, y: rect.minY + h))
        path.closeSubpath()
        return path
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "calendar") }
                .tag(AppTab.workouts)
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "dumbbell.fill") }
                .tag(AppTab.exercises)
            RankingsView()
                .tabItem { Label("Rankings", systemImage: "shield.lefthalf.filled") }
                .tag(AppTab.rankings)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        .fullScreenCover(isPresented: $appState.isWorkoutPresented) {
            if let session = appState.coverSession {
                ActiveWorkoutView(session: session)
            }
        }
        .sheet(item: $appState.finishedSummary) { summary in
            WorkoutSummaryView(summary: summary)
        }
        .sheet(isPresented: $appState.showFirstWorkoutGuide) {
            FirstWorkoutGuide()
        }
        .sheet(item: $appState.debugRoute) { route in
            NavigationStack {
                RouteDestination(route: route).primeDestinations()
            }
        }
        .overlay(alignment: .top) { ToastOverlay() }
    }
}

struct ToastOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let toast = appState.toast {
            ToastView(toast: toast)
                .padding(.top, 6)
                .padding(.horizontal, Theme.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { appState.toast = nil } }
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(toast.message).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch toast.style {
        case .record: return "trophy.fill"
        case .success: return "checkmark"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .record: return Theme.accent
        case .success: return Theme.accent
        case .warning: return Theme.warning
        }
    }
}
