import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    /// 音源を開く操作。画面の重なりは呼び出し側が持つ。
    var onOpen: (UUID) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var isImportingAudio = false
    @State private var subtitleTarget: Track?
    @State private var renameTarget: Track?
    @State private var renameText = ""
    @State private var clearLearnedTarget: Track?
    @State private var clearFavoritesTarget: Track?
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
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: Self.audioTypes,
            allowsMultipleSelection: true
        ) { result in
            handleAudioImport(result)
        }
        .fileImporter(
            isPresented: Binding(get: { subtitleTarget != nil },
                                 set: { if !$0 { subtitleTarget = nil } }),
            // .srt / .vtt は iOS に標準登録された型がないため、テキスト全般を許可する。
            // ここを狭めるとファイルアプリ上で字幕が選べなくなる。
            allowedContentTypes: [.plainText, .text, .data]
        ) { result in
            handleSubtitleImport(result)
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
        .alert("覚えた印をすべて消しますか?", isPresented: showClearLearnedBinding) {
            Button("キャンセル", role: .cancel) { clearLearnedTarget = nil }
            Button("すべて消す", role: .destructive) {
                if let target = clearLearnedTarget {
                    library.clearLearned(for: target.id)
                    if player.currentTrackID == target.id { player.applyLearned([]) }
                }
                clearLearnedTarget = nil
            }
        } message: {
            Text("この音源に付けた印がすべて消えます。元に戻せません。")
        }
        .alert("お気に入りをすべて消しますか?", isPresented: showClearFavoritesBinding) {
            Button("キャンセル", role: .cancel) { clearFavoritesTarget = nil }
            Button("すべて消す", role: .destructive) {
                if let target = clearFavoritesTarget {
                    library.clearFavorites(for: target.id)
                    if player.currentTrackID == target.id { player.applyFavorites([]) }
                }
                clearFavoritesTarget = nil
            }
        } message: {
            Text("この音源のお気に入りがすべて消えます。元に戻せません。")
        }
    }

    /// アラートは Optional の中身の有無で開閉するため、閉じられたら値も捨てる。
    private var showErrorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var showRenameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var showClearLearnedBinding: Binding<Bool> {
        Binding(get: { clearLearnedTarget != nil }, set: { if !$0 { clearLearnedTarget = nil } })
    }
    private var showClearFavoritesBinding: Binding<Bool> {
        Binding(get: { clearFavoritesTarget != nil }, set: { if !$0 { clearFavoritesTarget = nil } })
    }

    // MARK: - 一覧

    private var trackList: some View {
        List {
            // ひとつの箱にまとめて並べる。音源ごとに枠を分けると、件数が
            // 少なくても画面が余白で埋まってしまう。切れ目は区切り線で足りる。
            Section {
                ForEach(library.tracks) { track in
                    rowButton(for: track)
                        .contextMenu { menu(for: track) }
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
        }
        .listStyle(.insetGrouped)
    }

    private func rowButton(for track: Track) -> some View {
        Button {
            onOpen(track.id)
        } label: {
            HStack(spacing: 8) {
                row(for: track)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // 文字の無い余白も押せるようにする。行のどこを触っても開く。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trackRow")
        .accessibilityLabel(track.displayName)
    }

    /// 再生画面から帯を無くしたぶん、音源ごとの操作はここに集めている。
    @ViewBuilder
    private func menu(for track: Track) -> some View {
        Button {
            subtitleTarget = track
        } label: {
            Label(track.hasSubtitle ? "字幕を差し替え" : "字幕を追加", systemImage: "captions.bubble")
        }
        Button {
            renameText = track.displayName
            renameTarget = track
        } label: {
            Label("名前を変更", systemImage: "pencil")
        }
        Button(role: .destructive) {
            clearLearnedTarget = track
        } label: {
            Label("覚えた印をすべて消す", systemImage: "arrow.counterclockwise")
        }
        .disabled(track.learnedGroups.isEmpty)
        Button(role: .destructive) {
            clearFavoritesTarget = track
        } label: {
            Label("お気に入りをすべて消す", systemImage: "star.slash")
        }
        .disabled(track.favoriteGroups.isEmpty)
        Button(role: .destructive) {
            library.remove(track)
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    private func row(for track: Track) -> some View {
        // 名前だけを出す。字幕の有無や再生位置は開けば分かるため、
        // 一覧では省いて読みやすさを優先する。
        Text(track.displayName)
            .font(.body)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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

    private func handleSubtitleImport(_ result: Result<URL, Error>) {
        guard let target = subtitleTarget else { return }
        subtitleTarget = nil
        guard case .success(let url) = result else { return }
        do {
            try library.importSubtitle(from: url, for: target.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // 開いている音源なら、その場で字幕を読み直す
        if player.currentTrackID == target.id,
           let updated = library.tracks.first(where: { $0.id == target.id }) {
            player.loadSubtitles(from: library.subtitleURL(for: updated))
            player.applyLearned(library.learnedGroups(for: target.id, cueCount: player.cues.count))
        }
    }

    /// m4b(オーディオブック)や mp4 も選べるようにしておく。
    static let audioTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie]
}
