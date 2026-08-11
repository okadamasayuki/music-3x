import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    let track: Track

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    @State private var isImportingSubtitle = false
    @State private var showsTranscript = true
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var confirmClearLearned = false

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            display
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 20) {
                seekSection
                transportSection
                learnedSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .background(.bar)
        }
        .navigationTitle(liveTrack.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isImportingSubtitle,
            // .srt / .vtt は iOS に標準登録された型がないため、テキスト全般を許可する。
            // ここを狭めるとファイルアプリ上で字幕が選べなくなる。
            allowedContentTypes: [.plainText, .text, .data]
        ) { result in
            handleSubtitleImport(result)
        }
        .alert("覚えた印をすべて消しますか?", isPresented: $confirmClearLearned) {
            Button("キャンセル", role: .cancel) {}
            Button("すべて消す", role: .destructive) {
                library.clearLearned(for: track.id)
                player.applyLearned([])
            }
        } message: {
            Text("\(player.learnedGroups.count) 項目の印が消えます。元に戻せません。")
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - 表示部

    @ViewBuilder
    private var display: some View {
        if showsTranscript && player.hasSubtitles {
            TranscriptView(onToggleLearned: setLearned)
        } else {
            SubtitlePanel(
                cue: player.currentCue,
                hasSubtitles: player.hasSubtitles,
                onAddSubtitle: { isImportingSubtitle = true }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("表示", selection: $showsTranscript) {
                    Label("字幕を並べる", systemImage: "list.bullet").tag(true)
                    Label("1 行だけ大きく", systemImage: "textformat.size").tag(false)
                }
                .pickerStyle(.inline)
                .disabled(!player.hasSubtitles)

                Divider()

                Button {
                    isImportingSubtitle = true
                } label: {
                    Label(liveTrack.hasSubtitle ? "字幕を差し替え" : "字幕を追加",
                          systemImage: "captions.bubble")
                }

                Button(role: .destructive) {
                    confirmClearLearned = true
                } label: {
                    Label("覚えた印をすべて消す", systemImage: "trash")
                }
                .disabled(player.learnedGroups.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
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

    // MARK: - 覚えた項目の操作

    @ViewBuilder
    private var learnedSection: some View {
        if player.hasSubtitles && !player.groups.isEmpty {
            HStack(spacing: 10) {
                Button {
                    player.replayCurrentGroup()
                } label: {
                    Label("もう一度", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(player.activeGroupIndex == nil)

                Button {
                    guard let index = player.activeGroupIndex else { return }
                    setLearned(index, !player.learnedGroups.contains(index))
                } label: {
                    Label(isCurrentLearned ? "覚えた印を外す" : "この項目は覚えた",
                          systemImage: isCurrentLearned ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isCurrentLearned ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(isCurrentLearned ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(player.activeGroupIndex == nil)
                // 一覧側の丸印と同じ読み上げにならないよう、再生中の項目だと分かる言い方にする
                .accessibilityLabel(isCurrentLearned ? "再生中の項目の覚えた印を外す" : "再生中の項目を覚えた")
                .accessibilityIdentifier("markCurrentLearned")
            }
        }
    }

    private var isCurrentLearned: Bool {
        guard let index = player.activeGroupIndex else { return false }
        return player.learnedGroups.contains(index)
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

    private func handleSubtitleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        try? library.importSubtitle(from: url, for: track.id)
        player.loadSubtitles(from: library.subtitleURL(for: liveTrack))
        player.applyLearned(library.learnedGroups(for: track.id, cueCount: player.cues.count))
    }
}
