import SwiftUI

@main
struct Music3xApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                // 端末が夜間モードでも白地で使う。単語の一覧を長く眺める用途では
                // 黒地より白地のほうが読みやすいという求めによる。
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { phase in
                    // 「ファイル」アプリ等で音源が足された直後にも一覧へ反映されるように
                    if phase == .active { library.refresh() }
                }
        }
    }
}
