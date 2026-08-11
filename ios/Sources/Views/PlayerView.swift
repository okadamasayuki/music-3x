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
    /// 横向きの動きだと見極めがついたか。ついてから追従を始める。
    @State private var isDraggingBack = false

    /// 字幕の上を右へなぞると一覧へ戻る。
    /// 縦スクロールと取り合わないよう、横の動きが縦を上回ったときだけ追従する。
    private var backSwipe: some Gesture {
        // 画面自身をずらすので、移動量は画面に依存しない基準で測る。
        // 既定のまま(動く画面が基準)だと、ずらす→測り直すの繰り返しで震える。
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                if !isDraggingBack {
                    guard horizontal > 12, horizontal > vertical * 1.4 else { return }
                    isDraggingBack = true
                }
                onBackDragChanged(max(0, horizontal))
            }
            .onEnded { value in
                guard isDraggingBack else { return }
                isDraggingBack = false
                onBackDragEnded(max(0, value.translation.width),
                                max(0, value.predictedEndTranslation.width))
            }
    }

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(onToggleLearned: setLearned)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 戻る操作は字幕の領域だけで受ける。下の操作部に付けると、
                // 再生位置のスライダーを横に動かしただけで戻ってしまう。
                .simultaneousGesture(backSwipe)
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
                Spacer()
                Text(TimeFormatter.string(from: player.effectiveDuration))
                    .accessibilityIdentifier("duration")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 再生コントロール

    /// 設定した秒数に合う記号を選ぶ。用意のない秒数は数字なしの記号にする。
    private func skipSymbol(forward: Bool) -> String {
        let base = forward ? "goforward" : "gobackward"
        let available: Set<Int> = [5, 10, 15, 30, 45, 60, 75, 90]
        let n = Int(player.skipInterval.rounded())
        return available.contains(n) ? "\(base).\(n)" : base
    }

    private var skipSeconds: Int { Int(player.skipInterval.rounded()) }

    private var transportSection: some View {
        ZStack {
            transportButtons
            HStack {
                TranslationToggle()
                Spacer()
                speedLabel
            }
        }
    }

    /// 今の再生速度。操作は設定側にあるので、ここでは表示だけ。
    private var speedLabel: some View {
        Text(SpeedFormatter.label(for: player.speed))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(minWidth: 40, minHeight: 32)
            .accessibilityLabel("再生速度 \(SpeedFormatter.label(for: player.speed))")
            .accessibilityIdentifier("speed")
    }

    private var transportButtons: some View {
        HStack(spacing: 44) {
            Button {
                player.skip(-player.skipInterval)
            } label: {
                Image(systemName: skipSymbol(forward: false))
                    .font(.system(size: 30))
            }
            .accessibilityLabel("\(skipSeconds)秒戻る")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .disabled(!player.isReady)
            .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

            Button {
                player.skip(player.skipInterval)
            } label: {
                Image(systemName: skipSymbol(forward: true))
                    .font(.system(size: 30))
            }
            .accessibilityLabel("\(skipSeconds)秒進む")
        }
        .foregroundStyle(.tint)
    }

    // MARK: - 処理

    private func setLearned(_ group: Int, _ learned: Bool) {
        player.setLearned(learned, group: group)
        library.setLearned(learned, group: group, cueCount: player.cues.count, for: track.id)
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
        player.speed = settings.defaultSpeed
    }
}
