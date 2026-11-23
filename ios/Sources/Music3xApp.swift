import SwiftUI

@main
struct Music3xApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()
    @StateObject private var settings = AppSettings()
    @StateObject private var voice = VoiceCommands()
    @StateObject private var improvements = ImprovementStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(voice)
                .environmentObject(improvements)
                // 色の明暗は RootView が決める(一覧は白地、プレイヤーは暗い紺)
                .onChange(of: scenePhase) { phase in
                    // 「ファイル」アプリ等で音源が足された直後にも一覧へ反映されるように
                    if phase == .active { library.refresh() }
                }
        }
    }
}
