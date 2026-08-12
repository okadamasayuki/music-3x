import SwiftUI

struct PlayerView: View {
    let track: Track
    /// 戻るなぞり操作の進み具合。重なりを管理している側へ渡す。
    var onBackDragChanged: (CGFloat) -> Void = { _ in }
    var onBackDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(onToggleLearned: setLearned, onToggleFavorite: setFavorite)
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

            VStack(spacing: 10) {
                seekSection
                transportSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .onAppear(perform: loadIfNeeded)
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
            .disabled(player.effectiveDuration <= 0)

            HStack {
                Text(TimeFormatter.string(from: displayedTime))
                    .accessibilityIdentifier("elapsed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                favoriteRepeatButton
                Spacer()
                Text(TimeFormatter.string(from: player.effectiveDuration))
                    .accessibilityIdentifier("duration")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
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

    /// 左に訳の切り替え、中央に再生、右に速度。重ねて中央ぞろえにすると
    /// 速度の「−」が次の塊ボタンに重なるため、横一列に並べて場所を分ける。
    private var transportSection: some View {
        HStack(spacing: 0) {
            TranslationToggle()
            Spacer(minLength: 4)
            transportButtons
            Spacer(minLength: 4)
            speedStepper
        }
    }

    /// 再生速度。一覧から選ばせる形だと、行が狭いうえ真下に再生ボタンがあり、
    /// 押し損ねると何も起きずに閉じるだけになる。一段ずつ動かす形にして、
    /// 一度押せば必ず変わるようにした。
    private var speedStepper: some View {
        HStack(spacing: 2) {
            Button {
                stepSpeed(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(-1))
            .accessibilityIdentifier("speedDown")
            .accessibilityLabel("速度を下げる")

            Text(SpeedFormatter.label(for: player.speed))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 42)
                .accessibilityIdentifier("speed")
                .accessibilityLabel("再生速度 \(SpeedFormatter.label(for: player.speed))")

            Button {
                stepSpeed(1)
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(!canStepSpeed(1))
            .accessibilityIdentifier("speedUp")
            .accessibilityLabel("速度を上げる")
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
            .disabled(!player.hasPreviousGroup)
            .accessibilityIdentifier("previousGroup")
            .accessibilityLabel("前の塊へ")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .disabled(!player.isReady)
            .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

            Button {
                player.goToNextGroup()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26))
            }
            .disabled(!player.hasNextGroup)
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
        guard player.currentTrackID != track.id else { return }
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
}
