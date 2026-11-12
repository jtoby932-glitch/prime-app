import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(TrainingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Query private var profiles: [UserProfile]
    @State private var isReady = false
    @State private var setupError: String?

    private var profile: UserProfile? { profiles.first }

    private var motion: MotionPolicy {
        let chosen = AnimationLevel(rawValue: profile?.animationLevelRaw ?? "full") ?? .full
        if systemReduceMotion && chosen == .full { return MotionPolicy(level: .reduced) }
        return MotionPolicy(level: chosen)
    }

    var body: some View {
        // The accent is read by static tokens, so set it before any child is built.
        let _ = Self.syncAccent(profile?.accentRaw)
        ZStack {
            Theme.backdrop
            if !isReady {
                LaunchView(error: setupError)
                    .transition(.opacity)
            } else if profile?.hasCompletedOnboarding == true {
                MainTabView()
                    .id(profile?.accentRaw ?? "electric")
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .environment(\.motion, motion)
        .environment(\.bodyModel, BodyModel(rawValue: profile?.bodyModelRaw ?? "male") ?? .male)
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.35), value: isReady)
        .animation(.easeInOut(duration: 0.35), value: profile?.hasCompletedOnboarding)
        .task { await prepare() }
        .onChange(of: profile?.accentRaw) { _, _ in applyPreferences() }
        .onChange(of: profile?.hapticsEnabled) { _, _ in applyPreferences() }
        .onChange(of: scenePhase) { _, phase in
            guard isReady, phase == .active else { return }
            store.refresh(context)
            appState.refreshNotifications(context: context, history: store.history)
        }
    }

    @discardableResult
    static func syncAccent(_ raw: String?) -> Bool {
        Theme.accentChoice = AccentChoice(rawValue: raw ?? "electric") ?? .electric
        return true
    }

    private func applyPreferences() {
        Theme.accentChoice = AccentChoice(rawValue: profile?.accentRaw ?? "electric") ?? .electric
        Haptics.enabled = profile?.hapticsEnabled ?? true
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.accent)
    }

    private func prepare() async {
        guard !isReady else { return }
        let started = Date()
        do {
            try CatalogueService.seedIfNeeded(context: context)
        } catch {
            setupError = "The exercise library couldn't load: \(error.localizedDescription)"
        }
        ExerciseLibrary.shared.load()
        ScheduleService.ensureWeek(context: context)
        _ = DataService.profile(in: context)
        applyPreferences()
        UpgradeService.runIfNeeded(context: context, store: store)
        store.refresh(context)
        appState.restoreActiveSession(context: context)
        appState.refreshNotifications(context: context, history: store.history)
        #if DEBUG
        DemoData.apply(context: context, store: store, appState: appState)
        #endif
        // Let the mark finish drawing so launch doesn't flash.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.7 { try? await Task.sleep(nanoseconds: UInt64((0.7 - elapsed) * 1_000_000_000)) }
        isReady = true
    }
}

struct LaunchView: View {
    var error: String?

    var body: some View {
        VStack(spacing: 22) {
            LoadingMark(size: 64)
            Text("PRIME")
                .font(.system(size: 30, weight: .heavy).width(.expanded))
                .tracking(4)
                .foregroundStyle(Theme.textPrimary)
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

// MARK: - Tabs

/// Keeps every visited tab alive (so navigation state survives switching) and draws
/// PRIME's own tab bar with an animated selection indicator.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.motion) private var motion
    @State private var visited: Set<AppTab> = [.home]

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visited.contains(tab) {
                    let selected = appState.selectedTab == tab
                    tabContent(tab)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected || !motion.allowsMovement ? 1 : 0.985)
                        .offset(y: selected || !motion.allowsMovement ? 0 : 6)
                        .animation(motion.animation(.spring(response: 0.4, dampingFraction: 0.86)), value: appState.selectedTab)
                        .allowsHitTesting(selected)
                        .accessibilityHidden(appState.selectedTab != tab)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomChrome()
        }
        .onChange(of: appState.selectedTab) { _, tab in visited.insert(tab) }
        .onAppear { visited.insert(appState.selectedTab) }
        .fullScreenCover(isPresented: $appState.isWorkoutPresented) {
            if let session = appState.coverSession {
                ActiveWorkoutView(session: session)
            }
        }
        .sheet(item: $appState.finishedSummary) { summary in
            WorkoutSummaryView(summary: summary)
        }
        .sheet(isPresented: $appState.showSplitPresets) {
            SplitPresetPicker()
        }
        .sheet(isPresented: $appState.showSearch) {
            GlobalSearchView()
        }
        .sheet(item: $appState.rankEntry) { request in
            RankEntryView(initialSlug: request.exerciseSlug)
        }
        .fullScreenCover(item: $appState.reveal) { reveal in
            RankRevealView(reveal: reveal, initialStage: appState.revealStage, frozen: appState.revealFrozen)
        }
        .sheet(item: $appState.guideRequest) { request in
            ExerciseLoader(slug: request.id) { ExerciseGuideSheet(exercise: $0) }
        }
        .sheet(item: $appState.debugRoute) { route in
            NavigationStack { RouteDestination(route: route).primeDestinations() }
        }
        .overlay(alignment: .top) { ToastOverlay() }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .workouts: WorkoutsView()
        case .exercises: ExercisesView()
        case .rankings: RankingsView()
        case .profile: ProfileView()
        }
    }
}

struct BottomChrome: View {
    @Environment(AppState.self) private var appState
    @Environment(\.motion) private var motion

    var body: some View {
        VStack(spacing: 10) {
            if let session = appState.activeSession, !appState.isWorkoutPresented, session.modelContext != nil {
                ActiveWorkoutBar(session: session)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            PrimeTabBar()
        }
        .padding(.bottom, 4)
        .background(
            // Content fades out under the floating bar instead of hitting a hard edge.
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.85), Theme.background], startPoint: .top, endPoint: .bottom)
                .padding(.top, -36)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
        .animation(motion.animation(), value: appState.activeSession?.uuid)
    }
}

struct PrimeTabBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.motion) private var motion
    @Namespace private var indicator
    @State private var bounce: AppTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = appState.selectedTab == tab
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(motion.animation(.spring(response: 0.42, dampingFraction: 0.78))) { appState.selectedTab = tab }
                    bounce = tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if bounce == tab { bounce = nil } }
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if selected {
                                Capsule()
                                    .fill(Theme.accentGradient)
                                    .frame(width: 54, height: 32)
                                    .shadow(color: Theme.accent.opacity(0.55), radius: 10, y: 3)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                            Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                                .font(.system(size: 17, weight: selected ? .bold : .regular))
                                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                                .symbolEffect(.bounce.up, value: bounce == tab)
                        }
                        .frame(height: 32)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Theme.glassTint.opacity(0.78)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.18), Theme.border.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - Toasts

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
                Text(toast.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text(toast.message).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
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
        case .record: return Theme.warning
        case .success: return Theme.accentHighlight
        case .warning: return Theme.warning
        }
    }
}
