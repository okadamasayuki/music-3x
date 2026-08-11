import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("ライブラリ", systemImage: "music.note.list") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .onAppear {
            // 再生位置の保存はライブラリ側の責務なので、ここで橋渡しする
            player.onPositionChange = { [weak library] trackID, position in
                library?.updatePosition(position, for: trackID)
            }
            applySettings()
        }
        .onChange(of: settings.skipInterval) { _ in applySettings() }
        .onChange(of: settings.skipLearned) { _ in applySettings() }
    }

    private func applySettings() {
        player.skipInterval = settings.skipInterval
        player.skipLearned = settings.skipLearned
    }
}
