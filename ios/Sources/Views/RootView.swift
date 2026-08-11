import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Tab: Hashable { case library, settings }

    @State private var selectedTab: Tab = .library
    @State private var libraryPath = NavigationPath()

    /// 同じタブをもう一度押したら一覧へ戻す。再生画面から帯を無くしたため、
    /// これが戻る手段になる(左端スワイプは字幕のスクロールと競合して効かない)。
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { new in
                if new == .library && selectedTab == .library {
                    libraryPath = NavigationPath()
                }
                selectedTab = new
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $libraryPath) {
                LibraryView()
            }
            .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            .tag(Tab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(Tab.settings)
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
        .onChange(of: settings.defaultSpeed) { _ in applySettings() }
        .onChange(of: settings.showTranslation) { _ in applySettings() }
    }

    private func applySettings() {
        player.skipInterval = settings.skipInterval
        player.skipLearned = settings.skipLearned
        // 速度の操作はプレイヤー画面から外したので、設定を変えたら再生中でもすぐ反映する
        player.speed = settings.defaultSpeed
        player.showsTranslation = settings.showTranslation
    }
}
