import SwiftUI

struct PlayerView: View {
    let track: Track
    /// 今かかっている項目の字幕。別の音源を開いている間、小さい操作板に出す。
    var nowPlayingLines: [String] = []
    /// 今かかっている音源のプレイヤーを開く。小さい操作板を押したときに使う。
    var onOpenNowPlaying: () -> Void = {}
    /// 戻るなぞり操作の進み具合。重なりを管理している側へ渡す。
    var onBackDragChanged: (CGFloat) -> Void = { _ in }
    var onBackDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    /// 別の音源が鳴っている間に開いたときの、下読み用の字幕。
    /// 音を止めずに中身だけ見られるよう、再生機とは別に読み込む。
    @State private var previewCues: [SubtitleCue] = []
    @State private var previewGroups: [SubtitleGroup] = []

    /// この画面の音源が、いま再生機に載っているか。
    private var isLive: Bool { player.currentTrackID == track.id }

    /// いま鳴っている音源(この画面のものとは限らない)
    private var playingTrack: Track? {
        player.currentTrackID.flatMap { id in library.tracks.first { $0.id == id } }
    }

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLive {
                    TranscriptView(onToggleLearned: setLearned, onToggleFavorite: setFavorite)
                } else {
                    previewList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 戻る操作は字幕の領域だけで受ける。下の操作部に付けると、
            // 再生位置のスライダーを横に動かしただけで戻ってしまう。
            .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
            // 上端の字幕が時刻表示と重なって読みにくいので、そこだけ薄く消す
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.045),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            VStack(spacing: 0) {
                // 別の音源が鳴っている間は、その操作板をいつもの操作の上に載せる
                if !isLive, let playing = playingTrack {
                    MiniPlayerBar(
                        title: playing.displayName,
                        lines: nowPlayingLines,
                        isPlaying: player.isPlaying,
                        progress: player.effectiveDuration > 0
                            ? player.effectiveTime(for: player.currentTime) / player.effectiveDuration
                            : 0,
                        onOpen: onOpenNowPlaying,
                        onToggle: { player.togglePlayPause() }
                    )
                }

                VStack(spacing: 10) {
                    seekSection
                    transportSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .background(.bar)
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - 別の音源が鳴っている間の下読み

    /// 音を止めずに中身だけ並べる。印は付けられない(再生機を通さないため)ので、
    /// 印を付けたいときはフレーズタブを使う。
    private var previewList: some View {
        List {
            ForEach(previewGroups) { group in
                let lines = group.lines(in: previewCues)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(index == 0 ? .body : .subheadline)
                            .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .dynamicTypeSize(settings.textSize)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("previewList")
    }


    // MARK: - シーク

    /// 覚えて飛ばす分を除いた時間軸で表示する。聞く分量と目盛りを一致させるため。
    private var displayedTime: Double {
        isScrubbing ? scrubValue : player.effectiveTime(for: player.currentTime)
    }

    private var seekSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { newValue in
                        scrubValue = newValue
                        player.previewScrub(to: player.realTime(for: newValue))
                    }
                ),
                in: 0...max(player.effectiveDuration, 0.1)
            ) { editing in
                if editing {
                    isScrubbing = true
                    scrubValue = player.effectiveTime(for: player.currentTime)
                    player.beginScrubbing()
                } else {
                    isScrubbing = false
                    player.endScrubbing(at: player.realTime(for: scrubValue))
                }
            }
            .disabled(!isLive || player.effectiveDuration <= 0)

            HStack {
                Text(TimeFormatter.string(from: displayedTime))
                    .accessibilityIdentifier("elapsed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    repeatTrackButton
                    favoriteRepeatButton
                }
                Spacer()
                Text(TimeFormatter.string(from: player.effectiveDuration))
                    .accessibilityIdentifier("duration")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 最後まで行ったら先頭へ戻して流し続ける切り替え。
    private var repeatTrackButton: some View {
        let on = player.repeatTrack
        return Button {
            player.repeatTrack.toggle()
        } label: {
            Image(systemName: "repeat")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(on ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repeatTrack")
        .accessibilityLabel(on ? "繰り返しを止める" : "最後まで行ったら先頭から繰り返す")
    }

    /// お気に入りだけを続けて流す切り替え。入れている間は目盛りも
    /// お気に入りの合計に変わるので、残りがひと目で分かる。
    private var favoriteRepeatButton: some View {
        let count = player.favoriteGroups.count
        let on = player.repeatFavorites
        return Button {
            // 位置を先頭のお気に入りへ寄せるだけで、再生は始めない。
            // 押した拍子に鳴り出すと、印を確かめたいだけのときに邪魔になる。
            player.repeatFavorites.toggle()
        } label: {
            // 印そのものと同じ黄色の星だけを出す。個数は一覧の見出しで分かる。
            Image(systemName: "star.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.black.opacity(0.7) : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(on ? Color.yellow : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
        .accessibilityIdentifier("repeatFavorites")
        .accessibilityLabel(on ? "お気に入りの繰り返しを止める" : "お気に入りだけを繰り返す")
    }

    // MARK: - 再生コントロール

    /// 再生ボタンを画面の中央に置き、訳の切り替えと速度をその両脇へ寄せる。
    /// 速度を縦に積むことで横幅を取らず、中央ぞろえのまま重ならずに済む。
    private var transportSection: some View {
        ZStack {
            transportButtons
            HStack {
                TranslationToggle()
                Spacer()
                speedStepper
            }
        }
    }

    /// 再生速度。一覧から選ばせる形だと、行が狭いうえ真下に再生ボタンがあり、
    /// 押し損ねると何も起きずに閉じるだけになる。一段ずつ動かす形にして、
    /// 一度押せば必ず変わるようにした。
    private var speedStepper: some View {
        VStack(spacing: 0) {
            Button {
                stepSpeed(1)
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 48, height: 26)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(1))
            .accessibilityIdentifier("speedUp")
            .accessibilityLabel("速度を上げる")

            Text(SpeedFormatter.label(for: player.speed))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .frame(width: 48)
                .accessibilityIdentifier("speed")
                .accessibilityLabel("再生速度 \(SpeedFormatter.label(for: player.speed))")

            Button {
                stepSpeed(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 48, height: 26)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(-1))
            .accessibilityIdentifier("speedDown")
            .accessibilityLabel("速度を下げる")
        }
        .foregroundStyle(.tint)
    }

    /// 今の速度が刻みの何番目か。刻みに無い値なら、それ以下で一番近いものとみなす。
    private var speedIndex: Int {
        let choices = AppSettings.speedChoices
        if let exact = choices.firstIndex(where: { abs($0 - player.speed) < 0.001 }) { return exact }
        return choices.lastIndex(where: { $0 <= player.speed }) ?? 0
    }

    private func canStepSpeed(_ direction: Int) -> Bool {
        AppSettings.speedChoices.indices.contains(speedIndex + direction)
    }

    private func stepSpeed(_ direction: Int) {
        let target = speedIndex + direction
        guard AppSettings.speedChoices.indices.contains(target) else { return }
        apply(speed: AppSettings.speedChoices[target])
    }

    private var transportButtons: some View {
        // 秒数で送るより教材の切れ目で動くほうが聞き直しやすいので、
        // 送り戻しは前後の塊への移動にしてある。
        HStack(spacing: 16) {
            Button {
                player.goToPreviousGroup()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26))
            }
            .disabled(!isLive || !player.hasPreviousGroup)
            .accessibilityIdentifier("previousGroup")
            .accessibilityLabel("前の塊へ")

            Button {
                if isLive { player.togglePlayPause() } else { switchToThisTrack() }
            } label: {
                Image(systemName: isLive && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .disabled(isLive && !player.isReady)
            .accessibilityIdentifier(isLive ? "transport" : "switchToTrack")
            .accessibilityLabel(isLive && player.isPlaying ? "一時停止" : "再生")

            Button {
                player.goToNextGroup()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26))
            }
            .disabled(!isLive || !player.hasNextGroup)
            .accessibilityIdentifier("nextGroup")
            .accessibilityLabel("次の塊へ")
        }
        .foregroundStyle(.tint)
    }

    // MARK: - 処理

    /// 鳴っている音にその場で効かせ、次に開いたときも同じ速さで始まるようにする。
    private func apply(speed: Double) {
        player.speed = speed
        settings.defaultSpeed = speed
    }

    private func setLearned(_ group: Int, _ learned: Bool) {
        player.setLearned(learned, group: group)
        library.setLearned(learned, group: group, cueCount: player.cues.count, for: track.id)
    }

    private func setFavorite(_ group: Int, _ favorite: Bool) {
        player.setFavorite(favorite, group: group)
        library.setFavorite(favorite, group: group, cueCount: player.cues.count, for: track.id)
    }

    private func loadIfNeeded() {
        guard !isLive else { return }
        // 鳴っている最中に別の音源を開いても、音は止めない。中身だけ読んで並べ、
        // 切り替えるかどうかは「この音源を再生」を押したときに決める。
        if player.isPlaying {
            loadPreview()
            return
        }
        loadIntoPlayer()
    }

    private func loadPreview() {
        guard previewGroups.isEmpty else { return }
        guard let url = library.subtitleURL(for: liveTrack) else { return }
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS)) ?? ""
        previewCues = SubtitleParser.parse(content)
        previewGroups = previewCues.grouped()
    }

    private func loadIntoPlayer() {
        let current = liveTrack
        player.load(
            audioURL: library.audioURL(for: current),
            subtitleURL: library.subtitleURL(for: current),
            title: current.displayName,
            trackID: current.id,
            startAt: current.lastPosition
        )
        player.applyLearned(library.learnedGroups(for: current.id, cueCount: player.cues.count))
        player.applyFavorites(library.favoriteGroups(for: current.id, cueCount: player.cues.count))
        player.speed = settings.defaultSpeed
    }

    /// 下読みしていた音源へ切り替えて鳴らし始める。
    private func switchToThisTrack() {
        loadIntoPlayer()
        previewCues = []
        previewGroups = []
        player.play()
    }
}
