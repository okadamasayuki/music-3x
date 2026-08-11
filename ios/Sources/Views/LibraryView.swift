import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var isImportingAudio = false
    @State private var renameTarget: Track?
    @State private var renameText = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .navigationTitle("ライブラリ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImportingAudio = true
                } label: {
                    Label("音源を追加", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: Self.audioTypes,
            allowsMultipleSelection: true
        ) { result in
            handleAudioImport(result)
        }
        .alert("読み込めませんでした", isPresented: showErrorBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("名前を変更", isPresented: showRenameBinding) {
            TextField("名前", text: $renameText)
            Button("キャンセル", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget { library.rename(target, to: renameText) }
                renameTarget = nil
            }
        }
    }

    /// アラートは Optional の中身が有無で開閉するため、閉じられたら値も捨てる。
    /// .constant で束縛すると閉じる操作が状態に反映されず開きっぱなしになる。
    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var showRenameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    // MARK: - 一覧

    private var trackList: some View {
        List {
            ForEach(library.tracks) { track in
                NavigationLink(value: track.id) {
                    row(for: track)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        library.remove(track)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                    Button {
                        renameText = track.displayName
                        renameTarget = track
                    } label: {
                        Label("名前", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationDestination(for: UUID.self) { trackID in
            if let track = library.tracks.first(where: { $0.id == trackID }) {
                PlayerView(track: track)
            }
        }
    }

    private func row(for track: Track) -> some View {
        HStack(spacing: 12) {
            Image(systemName: player.currentTrackID == track.id && player.isPlaying
                  ? "waveform" : "music.note")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayName)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if track.hasSubtitle {
                        Label("字幕あり", systemImage: "captions.bubble")
                    }
                    if track.lastPosition > 5 {
                        Label(TimeFormatter.string(from: track.lastPosition) + " から", systemImage: "clock.arrow.circlepath")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("音源がまだありません")
                .font(.title3.weight(.semibold))

            Text("「ファイル」アプリや iCloud Drive から\nMP3 / M4A / WAV などを追加できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isImportingAudio = true
            } label: {
                Label("音源を追加", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }

    // MARK: - 取り込み

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    try library.importAudio(from: url)
                } catch {
                    errorMessage = "\(url.lastPathComponent) を取り込めませんでした。\n\(error.localizedDescription)"
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// m4b(オーディオブック)や mp4 も選べるようにしておく。
    static let audioTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie]
}
