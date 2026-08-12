import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Tab: Hashable { case library, phrases, settings }

    /// 帯より手前に重ねる画面。どちらもタブの帯まで覆う。
    private enum Opened: Equatable {
        case player(UUID)
        case phrases(UUID)

        var trackID: UUID {
            switch self {
            case .player(let id), .phrases(let id): return id
            }
        }
    }

    @State private var selectedTab: Tab = .library
    @State private var opened: Opened?
    /// 手前の画面を右へずらしている量。0 なら開いた状態。
    @State private var dragX: CGFloat = 0

    private var openedTrack: Track? {
        opened.flatMap { o in library.tracks.first(where: { $0.id == o.trackID }) }
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

                // タブより手前に重ねる。帯まで覆うことで、字幕に使える範囲が広がる。
                if let opened, let track = openedTrack {
                    Group {
                        switch opened {
                        case .player:
                            PlayerView(
                                track: track,
                                onBackDragChanged: { dragX = max(0, $0) },
                                onBackDragEnded: { translation, predicted in
                                    finish(translation: translation, predicted: predicted, width: width)
                                }
                            )
                        case .phrases:
                            PhraseDetailView(
                                track: track,
                                onBackDragChanged: { dragX = max(0, $0) },
                                onBackDragEnded: { translation, predicted in
                                    finish(translation: translation, predicted: predicted, width: width)
                                }
                            )
                        }
                    }
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
                LibraryView(onOpen: { open(.player($0)) })
            }
            .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            .tag(Tab.library)

            NavigationStack {
                PhraseListView(onOpen: { open(.phrases($0)) })
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

    private func open(_ target: Opened) {
        dragX = 0
        withAnimation(.easeOut(duration: 0.28)) { opened = target }
    }

    /// 指を離したとき、戻しきるか元へ返すかを決める。
    private func finish(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        let enough = translation > width * 0.3 || predicted > width * 0.6
        if enough {
            withAnimation(.easeOut(duration: 0.22)) { dragX = width }
            // ずれきってから実体を外す。先に外すと画面が一瞬飛んで見える。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                opened = nil
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
