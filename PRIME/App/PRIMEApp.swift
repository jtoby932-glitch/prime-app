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
        }
    }
}

enum Appearance {
    static func configure() {
        let titleColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        let navy = UIColor(red: 0.02, green: 0.03, blue: 0.045, alpha: 0.82)

        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.largeTitleTextAttributes = [.foregroundColor: titleColor, .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 32, weight: .bold))]
        transparent.titleTextAttributes = [.foregroundColor: titleColor, .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        scrolled.backgroundColor = navy
        scrolled.shadowColor = UIColor(red: 0.11, green: 0.17, blue: 0.26, alpha: 1)
        scrolled.largeTitleTextAttributes = transparent.largeTitleTextAttributes
        scrolled.titleTextAttributes = transparent.titleTextAttributes

        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = transparent

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(red: 0.22, green: 0.48, blue: 1, alpha: 1)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.75)], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(red: 0.063, green: 0.102, blue: 0.176, alpha: 1)
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
                .foregroundStyle(Theme.textPrimary)
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
