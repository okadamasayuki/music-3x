import SwiftUI

struct PlayerView: View {
    let track: Track

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(onToggleLearned: setLearned)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 20) {
                seekSection
                transportSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .background(.bar)
        }
        // 字幕を少しでも広く使うため、画面上部の帯は出さない。
        .toolbar(.hidden, for: .navigationBar)
        // 帯を消すと iOS 標準の戻るスワイプも無効になるため、自前で受け取る。
        // 縦スクロールを邪魔しないよう、横に大きく振れたときだけ戻す。
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    if horizontal > 80, vertical < horizontal * 0.7 {
                        dismiss()
                    }
                }
        )
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
        HStack(spacing: 40) {
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
