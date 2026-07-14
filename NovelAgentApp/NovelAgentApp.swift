import SwiftUI

@main
struct NovelAgentApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appModel)
                .tint(AppTheme.accent)
        }
    }
}

