import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Tab: Hashable { case library, phrases, settings }

    @State private var selectedTab: Tab = .library
    @State private var openedTrackID: UUID?

    /// 同じタブをもう一度押したら一覧へ戻す。なぞって戻す操作の補助。
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { new in
                if new == .library && selectedTab == .library {
                    withAnimation(.easeOut(duration: 0.24)) { openedTrackID = nil }
                }
                selectedTab = new
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            LibraryTab(openedTrackID: $openedTrackID)
                .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
                .tag(Tab.library)

            NavigationStack {
                PhraseListView()
            }
            .tabItem { Label("フレーズ", systemImage: "checklist") }
            .tag(Tab.phrases)

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
