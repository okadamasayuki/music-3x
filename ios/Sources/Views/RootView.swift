import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Tab: Hashable { case library, phrases, settings }

    @State private var selectedTab: Tab = .library
    @State private var openedTrackID: UUID?
    /// 再生画面を右へずらしている量。0 なら開いた状態。
    @State private var dragX: CGFloat = 0

    private var openedTrack: Track? {
        openedTrackID.flatMap { id in library.tracks.first(where: { $0.id == id }) }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(max(dragX / width, 0), 1)   // 0=開いている 1=閉じきった
            let isOpen = openedTrack != nil

            ZStack(alignment: .leading) {
                tabs
                    // 奥の画面はわずかに左へ寄せておき、戻すにつれて定位置へ返す
                    .offset(x: isOpen ? -width * 0.22 * (1 - progress) : 0)
                    .overlay(
                        Color.black
                            .opacity(isOpen ? 0.18 * (1 - progress) : 0)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    )

                // 再生画面はタブより手前に重ねる。タブの帯まで覆うことで、
                // 字幕に使える範囲が広がる。
                if let track = openedTrack {
                    PlayerView(
                        track: track,
                        onBackDragChanged: { dragX = max(0, $0) },
                        onBackDragEnded: { translation, predicted in
                            finish(translation: translation, predicted: predicted, width: width)
                        }
                    )
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .offset(x: dragX)
                    .shadow(color: .black.opacity(0.3), radius: 12, x: -6)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                }
            }
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

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(onOpen: open)
            }
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
    }

    private func open(_ id: UUID) {
        dragX = 0
        withAnimation(.easeOut(duration: 0.28)) { openedTrackID = id }
    }

    /// 指を離したとき、戻しきるか元へ返すかを決める。
    private func finish(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        let enough = translation > width * 0.3 || predicted > width * 0.6
        if enough {
            withAnimation(.easeOut(duration: 0.22)) { dragX = width }
            // ずれきってから実体を外す。先に外すと画面が一瞬飛んで見える。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                openedTrackID = nil
                dragX = 0
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragX = 0 }
        }
    }

    private func applySettings() {
        player.skipInterval = settings.skipInterval
        player.skipLearned = settings.skipLearned
        // 速度の操作はプレイヤー画面から外したので、設定を変えたら再生中でもすぐ反映する
        player.speed = settings.defaultSpeed
        player.showsTranslation = settings.showTranslation
    }
}
