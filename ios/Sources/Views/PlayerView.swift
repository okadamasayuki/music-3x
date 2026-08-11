import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    let track: Track

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var isImportingSubtitle = false
    @State private var showsCueList = false
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    /// ライブラリ側が更新される(字幕を後から足す等)ので、常に最新を引き直す。
    private var liveTrack: Track {
        library.tracks.first(where: { $0.id == track.id }) ?? track
    }

    var body: some View {
        VStack(spacing: 0) {
            SubtitlePanel(
                cue: player.currentCue,
                hasSubtitles: player.hasSubtitles,
                onAddSubtitle: { isImportingSubtitle = true }
            )
            .frame(maxHeight: .infinity)

            VStack(spacing: 24) {
                seekSection
                transportSection
                SpeedControlView()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background(.bar)
        }
        .navigationTitle(liveTrack.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isImportingSubtitle = true
                    } label: {
                        Label(liveTrack.hasSubtitle ? "字幕を差し替え" : "字幕を追加", systemImage: "captions.bubble")
                    }
                    Button {
                        showsCueList = true
                    } label: {
                        Label("字幕を一覧で見る", systemImage: "list.bullet")
                    }
                    .disabled(!player.hasSubtitles)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsCueList) {
            CueListView()
        }
        .fileImporter(
            isPresented: $isImportingSubtitle,
            // .srt / .vtt は iOS に標準登録された型がないため、テキスト全般を許可する。
            // ここを狭めるとファイルアプリ上で字幕が選べなくなる。
            allowedContentTypes: [.plainText, .text, .data]
        ) { result in
            handleSubtitleImport(result)
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - シーク

    private var seekSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : player.currentTime },
                    set: { newValue in
                        scrubValue = newValue
                        player.previewScrub(to: newValue)
                    }
                ),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if editing {
                    isScrubbing = true
                    scrubValue = player.currentTime
                    player.beginScrubbing()
                } else {
                    isScrubbing = false
                    player.endScrubbing(at: scrubValue)
                }
            }
            .disabled(player.duration <= 0)

            HStack {
                Text(TimeFormatter.string(from: isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(TimeFormatter.string(from: player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 再生コントロール

    private var transportSection: some View {
        HStack(spacing: 44) {
            Button {
                player.skip(-PlayerEngine.skipInterval)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 32))
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }
            .disabled(!player.isReady)

            Button {
                player.skip(PlayerEngine.skipInterval)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 32))
            }
        }
        .foregroundStyle(.tint)
    }

    // MARK: - 処理

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
    }

    private func handleSubtitleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        try? library.importSubtitle(from: url, for: track.id)
        player.loadSubtitles(from: library.subtitleURL(for: liveTrack))
    }
}
