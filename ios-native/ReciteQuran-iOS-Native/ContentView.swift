import SwiftUI

struct ContentView: View {
    @State private var coordinator = RecitationCoordinator()

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--selftest") {
            SelfTestView()
        } else {
          Group {
            if coordinator.isReady {
                TrackingScreen(coordinator: coordinator)
            } else {
                SplashView(status: coordinator.errorMessage ?? coordinator.status,
                           colors: coordinator.appState.colors)
            }
        }
        .preferredColorScheme(coordinator.appState.theme == .dark ? .dark : .light)
        .environment(coordinator.appState)
        .task { await coordinator.initialize() }
        }
    }
}

private struct SplashView: View {
    let status: String
    let colors: ThemeColors
    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            VStack(spacing: 28) {
                Text("وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ")
                    .font(.custom(FontRegistrar.fontName, size: 34))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colors.gold)
                ProgressView().tint(colors.gold)
                Text(status).font(.subheadline).foregroundStyle(colors.muted)
            }.padding(32)
        }
    }
}

#Preview { ContentView() }
