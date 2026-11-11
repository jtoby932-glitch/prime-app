import SwiftData
import SwiftUI
import UIKit

@main
struct PRIMEApp: App {
    @State private var appState = AppState()
    @State private var store = TrainingStore()
    private let container: Result<ModelContainer, Error>

    init() {
        container = Result(catching: { try PrimeStore.makeContainer() })
        NotificationService.shared.activate()
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch container {
                case .success(let container):
                    RootView()
                        .environment(appState)
                        .environment(store)
                        .modelContainer(container)
                case .failure(let error):
                    StoreErrorView(message: error.localizedDescription)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }
}

enum Appearance {
    static func configure() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tab.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.024, alpha: 0.78)
        tab.shadowColor = UIColor.white.withAlphaComponent(0.06)
        let accent = UIColor(Theme.accent)
        let idle = UIColor(Theme.textTertiary)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = [.foregroundColor: accent]
            layout.normal.iconColor = idle
            layout.normal.titleTextAttributes = [.foregroundColor: idle]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = .clear
        let large = UIFont.systemFont(ofSize: 34, weight: .heavy)
        let condensed = large.fontDescriptor.withSymbolicTraits(.traitCondensed).map { UIFont(descriptor: $0, size: 34) } ?? large
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: condensed)]
        nav.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        UINavigationBar.appearance().standardAppearance = {
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithDefaultBackground()
            scrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
            scrolled.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.024, alpha: 0.7)
            scrolled.shadowColor = .clear
            scrolled.largeTitleTextAttributes = nav.largeTitleTextAttributes
            scrolled.titleTextAttributes = nav.titleTextAttributes
            return scrolled
        }()
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        UISegmentedControl.appearance().selectedSegmentTintColor = accent
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.8)], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(Theme.card)
    }
}

/// Shown only if the database can't be opened. Nothing is deleted automatically.
struct StoreErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.warning)
            Text("PRIME couldn't open your data")
                .font(.primeTitle)
                .foregroundStyle(.white)
            Text("Your workouts haven't been deleted. Close PRIME completely and open it again. If this keeps happening, free up some storage on your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
