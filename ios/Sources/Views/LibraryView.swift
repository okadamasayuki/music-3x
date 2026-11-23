import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    /// 音源を開く操作。画面の重なりは呼び出し側が持つ。
    var onOpen: (UUID) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var isImportingAudio = false
    @State private var renameTarget: Track?
    @State private var renameText = ""
    @State private var errorMessage: String?
    /// 音源ごとの項目数(覚えた割合を出すため)。字幕を読んで数える。
    @State private var groupCounts: [UUID: Int] = [:]

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .navigationTitle("英→日")
        .navigationBarTitleDisplayMode(.inline)
        // 見出しは一覧の中に自前で置く(プレイヤーと同じ見た目にそろえるため)
        .toolbar(.hidden, for: .navigationBar)
        .background(NightBackdrop().ignoresSafeArea())
        .task(id: library.tracks.map(\.id)) { await countGroups() }
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

    /// アラートは Optional の中身の有無で開閉するため、閉じられたら値も捨てる。
    private var showErrorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var showRenameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    // MARK: - 一覧

    private var trackList: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))

            ForEach(library.tracks) { track in
                rowButton(for: track)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
            // 長押しで持ち上げて、上下に並べ替える
            .onMove { source, destination in
                library.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LIBRARY")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Night.cyan)
            Text("英→日")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    private func rowButton(for track: Track) -> some View {
        let isCurrent = player.currentTrackID == track.id
        return Button {
            onOpen(track.id)
        } label: {
            HStack(spacing: 14) {
                trackTile(isCurrent: isCurrent)
                row(for: track, isCurrent: isCurrent)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isCurrent ? Night.cyan.opacity(0.10) : Color.white.opacity(0.06))
                    .shadow(color: isCurrent ? Night.cyan.opacity(0.18) : .clear, radius: 14)
            }
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Night.cyan.opacity(0.6), Night.blue.opacity(0.15)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                } else {
                    GlassEdge(cornerRadius: 22)
                }
            }
            // 文字の無い余白も押せるようにする。行のどこを触っても開く。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trackRow")
        .accessibilityLabel(track.displayName)
    }

    /// 音源の印。今開いている音源は光らせ、鳴っているか止まっているかも示す。
    /// 一覧に戻ったとき、どれの続きなのか探し直さずに済むようにするため。
    private func trackTile(isCurrent: Bool) -> some View {
        let symbol = isCurrent ? (player.isPlaying ? "waveform" : "pause.fill") : "play.fill"
        return ZStack {
            if isCurrent {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Night.glow)
                    .shadow(color: Night.blue.opacity(0.5), radius: 10, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isCurrent ? Color.white : Night.cyan)
        }
        .frame(width: 46, height: 46)
        .accessibilityIdentifier(isCurrent ? "nowPlayingMark" : "trackTile")
        .accessibilityLabel(isCurrent ? (player.isPlaying ? "再生中" : "一時停止中") : "")
    }

    private func row(for track: Track, isCurrent: Bool) -> some View {
        // 名前を主にし、覚えた割合を細い帯で添える。字幕の有無や再生位置は
        // 開けば分かるため、一覧では省いて読みやすさを優先する。
        VStack(alignment: .leading, spacing: 6) {
            if isCurrent {
                Text(player.isPlaying ? "NOW PLAYING" : "PAUSED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Night.cyan)
            }
            Text(track.displayName)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let total = groupCounts[track.id], total > 0 {
                let learned = min(track.learnedGroups.count, total)
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [Night.green, Night.cyan],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(geo.size.width * CGFloat(learned) / CGFloat(total),
                                                  learned > 0 ? 3 : 0))
                        }
                    }
                    .frame(width: 90, height: 4)
                    Text("覚えた \(learned) / \(total)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 字幕を読んで項目数を数える。音源が足されたり消されたりしたら数え直す。
    private func countGroups() async {
        let targets = library.tracks.compactMap { track in
            library.subtitleURL(for: track).map { (track.id, $0) }
        }
        let counts = await Task.detached(priority: .utility) { () -> [UUID: Int] in
            var result: [UUID: Int] = [:]
            for (id, url) in targets {
                let content = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .shiftJIS)) ?? ""
                result[id] = SubtitleParser.parse(content).grouped().count
            }
            return result
        }.value
        groupCounts = counts
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "character.bubble")
                .font(.system(size: 52))
                .foregroundStyle(Night.cyan)

            Text("音源がまだありません")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

            Text("「ファイル」アプリや iCloud Drive から\nMP3 / M4A / WAV などを追加できます。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button {
                isImportingAudio = true
            } label: {
                Label("音源を追加", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Night.blue)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
