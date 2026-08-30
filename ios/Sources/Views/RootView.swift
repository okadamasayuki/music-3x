import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var voice: VoiceCommands

    private enum Tab: Hashable { case library, phrases, improve, settings }

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
    /// 画面の横幅。開くときの初期位置(画面の外)を決めるために覚えておく。
    @State private var screenWidth: CGFloat = 0
    /// 声で直前に切り替えた項目。言い直しで戻せるように覚えておく。
    @State private var lastVoiceToggle: (group: Int, becameLearned: Bool)?

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
                                nowPlayingLines: currentLines,
                                onOpenNowPlaying: {
                                    if let id = player.currentTrackID { open(.player(id)) }
                                },
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
                    // 入場効果(transition)は使わない。位置移動と薄れが混ざり、
                    // 中身だけが全幅に薄く描かれて残像のように見えるため。
                    // 位置は dragX だけで動かす。
                    .zIndex(1)
                }
            }
            .onAppear { screenWidth = width }
            .onChange(of: width) { screenWidth = $0 }
        }
        .onAppear {
            // 再生位置の保存はライブラリ側の責務なので、ここで橋渡しする
            player.onPositionChange = { [weak library] trackID, position in
                library?.updatePosition(position, for: trackID)
            }
            applySettings()
            // 無音検証。ふだんの起動では何もしない(SkipAudit 参照)
            SkipAudit.startIfRequested(player: player, library: library)
            voice.onMatch = { group in toggleLearned(group) }
            voice.onUndo = { undoLastToggle() }
            voice.focusGroup = { player.activeGroupIndex ?? player.highlightedGroupIndex }
            updateVoice()
        }
        .onChange(of: settings.skipInterval) { _ in applySettings() }
        .onChange(of: settings.skipLearned) { _ in applySettings() }
        .onChange(of: settings.defaultSpeed) { _ in applySettings() }
        .onChange(of: settings.showTranslation) { _ in applySettings() }
        .onChange(of: settings.voiceControl) { _ in updateVoice() }
        .onChange(of: player.currentTrackID) { _ in updateVocabulary() }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(onOpen: { open(.player($0)) })
                    .safeAreaInset(edge: .bottom) { miniPlayer }
            }
            .tabItem { Label("ライブラリ", systemImage: "music.note.list") }
            .tag(Tab.library)

            NavigationStack {
                PhraseListView(onOpen: { open(.phrases($0)) })
                    .safeAreaInset(edge: .bottom) { miniPlayer }
            }
            .tabItem { Label("フレーズ", systemImage: "checklist") }
            .tag(Tab.phrases)

            NavigationStack {
                ImprovementListView()
                    .safeAreaInset(edge: .bottom) { miniPlayer }
            }
            .tabItem { Label("改善", systemImage: "lightbulb") }
            .tag(Tab.improve)

            NavigationStack {
                SettingsView()
                    .safeAreaInset(edge: .bottom) { miniPlayer }
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
    }

    /// 今かかっている音源。プレイヤー画面を閉じても操作を残すために使う。
    private var playingTrack: Track? {
        player.currentTrackID.flatMap { id in library.tracks.first { $0.id == id } }
    }

    /// 今かかっている項目の字幕。読み直しはまとめてあるので数行しか出ない。
    /// 訳を伏せる設定なら英文だけにして、プレイヤー画面と食い違わないようにする。
    private var currentLines: [String] {
        guard let index = player.highlightedGroupIndex,
              player.groups.indices.contains(index) else { return [] }
        let lines = player.groups[index].lines(in: player.cues).map(\.text)
        guard !settings.showTranslation else { return lines }
        let english = lines.filter { !$0.looksLikeTranslation }
        return english.isEmpty ? lines : english
    }

    /// タブの帯のすぐ上に出す小さい操作板。
    /// 画面を離れても鳴り続けるので、止める・戻るための手がかりを残しておく。
    @ViewBuilder
    private var miniPlayer: some View {
        if opened == nil, let track = playingTrack {
            MiniPlayerBar(
                title: track.displayName,
                lines: currentLines,
                isPlaying: player.isPlaying,
                progress: player.effectiveDuration > 0
                    ? player.effectiveTime(for: player.currentTime) / player.effectiveDuration
                    : 0,
                onOpen: { open(.player(track.id)) },
                onToggle: { player.togglePlayPause() }
            )
        }
    }

    /// 画面の外(右)へ置いてから、その場へ滑らせる。
    private func open(_ target: Opened) {
        let width = max(screenWidth, 1)
        opened = target
        dragX = width
        // 置いた直後に動かす。同じ描画のうちに動かすと、初期位置が無視される。
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.28)) { dragX = 0 }
        }
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

    private func updateVoice() {
        if settings.voiceControl {
            updateVocabulary()
            voice.start()
        } else {
            voice.stop()
            voice.vocabulary = [:]
            // 録音のために変えた音の設定を、再生だけの形へ戻す
            player.configureAudioSession()
        }
    }

    /// 声で指せる語の表を組み直す。使うときだけ作る。
    private func updateVocabulary() {
        guard settings.voiceControl, !player.groups.isEmpty else {
            voice.vocabulary = [:]
            return
        }
        voice.vocabulary = player.groups.spokenVocabulary(in: player.cues)
    }

    /// 聞き取った単語の項目の、覚えた印を入れ替える。
    /// すでに付いていれば外す。付けたのと同じ言い方で戻せるようにするため。
    /// 返すのは、その結果として印が付いたかどうか。
    @discardableResult
    private func toggleLearned(_ group: Int) -> Bool {
        guard let trackID = player.currentTrackID else { return false }
        let learned = !player.learnedGroups.contains(group)
        player.setLearned(learned, group: group)
        library.setLearned(learned, group: group, cueCount: player.cues.count, for: trackID)
        // 画面を見ずに使うので、振動で返す。付けたときと外したときで手触りを変える。
        UIImpactFeedbackGenerator(style: learned ? .medium : .soft).impactOccurred()
        lastVoiceToggle = (group, learned)
        return learned
    }

    /// 声で直前に切り替えた項目を元へ戻す。返すのは戻した単語。
    private func undoLastToggle() -> String? {
        guard let last = lastVoiceToggle,
              let trackID = player.currentTrackID,
              player.groups.indices.contains(last.group) else { return nil }
        let back = !last.becameLearned
        player.setLearned(back, group: last.group)
        library.setLearned(back, group: last.group, cueCount: player.cues.count, for: trackID)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        lastVoiceToggle = nil
        let lines = player.groups[last.group].lines(in: player.cues)
            .map(\.text).filter { !$0.looksLikeTranslation }
        return lines.first ?? "直前の項目"
    }

    private func applySettings() {
        player.skipInterval = settings.skipInterval
        player.skipLearned = settings.skipLearned
        // 速度の操作はプレイヤー画面から外したので、設定を変えたら再生中でもすぐ反映する
        player.speed = settings.defaultSpeed
        player.showsTranslation = settings.showTranslation
    }
}

/// タブの帯のすぐ上に出す、小さい再生操作板。
/// 帯を押すとプレイヤー画面へ戻り、右端のボタンで止め直せる。
struct MiniPlayerBar: View {
    let title: String
    /// 今かかっている項目の字幕。空なら音源の名前を出す。
    let lines: [String]
    let isPlaying: Bool
    /// 0〜1。細い線で今どのあたりかを示す。
    let progress: Double
    var onOpen: () -> Void
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                // 帯が厚くなりすぎないよう 2 行までにする。
                // ここは読むための場所ではなく、今どこかを知るための表示。
                if lines.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(index == 0 ? .subheadline.weight(.medium) : .caption)
                                .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // 目盛りは細い線だけにする。数字まで出すと帯が厚くなる。
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(Color.accentColor)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 2)
            }

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("miniPlayerToggle")
            .accessibilityLabel(isPlaying ? "一時停止" : "再生")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .opaqueBar()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        // 中の再生ボタンを外から押せるよう、ひとまとめにはしない
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniPlayer")
        .accessibilityLabel("再生中: \(title)")
    }
}
