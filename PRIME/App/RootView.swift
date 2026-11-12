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
                    tabContent(tab)
                        .opacity(appState.selectedTab == tab ? 1 : 0)
                        .offset(y: appState.selectedTab == tab || !motion.allowsMovement ? 0 : 8)
                        .allowsHitTesting(appState.selectedTab == tab)
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
        VStack(spacing: 8) {
            if let session = appState.activeSession, !appState.isWorkoutPresented, session.modelContext != nil {
                ActiveWorkoutBar(session: session)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            PrimeTabBar()
        }
        .animation(motion.animation(), value: appState.activeSession?.uuid)
    }
}

struct PrimeTabBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.motion) private var motion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = appState.selectedTab == tab
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(motion.animation(.spring(response: 0.38, dampingFraction: 0.82))) { appState.selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent.opacity(0.18))
                                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                                    .frame(width: 52, height: 30)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                            Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                                .font(.system(size: 17, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.accentHighlight : Theme.textSecondary)
                                .scaleEffect(selected && motion.allowsMovement ? 1.06 : 1)
                        }
                        .frame(height: 30)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(hex: 0x05070B).opacity(0.72))
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
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
