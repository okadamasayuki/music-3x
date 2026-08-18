import SwiftUI

/// 音源を選んでからフレーズを見る。ライブラリと同じ並びにしておくと、
/// どの教材の分を見ているのか迷わない。
struct PhraseListView: View {
    /// フレーズ一覧を開く操作。画面の重なりは呼び出し側が持つ。
    var onOpen: (UUID) -> Void

    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                emptyState
            } else {
                List {
                    // ライブラリと同じく、ひとつの箱にまとめて並べる
                    Section {
                        ForEach(library.tracks) { track in
                            Button {
                                onOpen(track.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(track.displayName)
                                        .font(.body)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("trackRow")
                            .accessibilityLabel(track.displayName)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tightTop()
            }
        }
        .navigationTitle("フレーズ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("音源がまだありません")
                .font(.title3.weight(.semibold))
            Text("ライブラリに字幕付きの音源を入れると、\nここでフレーズを一覧できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

/// 音声を鳴らさずに、フレーズを見ながら印を付けるための画面。
/// 再生中かどうかに関わらず開けるよう、字幕はここで読み込む。
struct PhraseDetailView: View {
    let track: Track
    /// 戻るなぞり操作の進み具合。重なりを管理している側へ渡す。
    var onBackDragChanged: (CGFloat) -> Void = { _ in }
    var onBackDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Filter: String, CaseIterable, Identifiable {
        case all, unlearned, learned
        var id: String { rawValue }
    }

    @State private var cues: [SubtitleCue] = []
    @State private var allGroups: [SubtitleGroup] = []
    @State private var learned: Set<Int> = []
    @State private var filter: Filter = .all

    private var groups: [SubtitleGroup] {
        switch filter {
        case .all: return allGroups
        case .unlearned: return allGroups.filter { !learned.contains($0.id) }
        case .learned: return allGroups.filter { learned.contains($0.id) }
        }
    }

    var body: some View {
        Group {
            if allGroups.isEmpty {
                noSubtitle
            } else {
                VStack(spacing: 0) {
                    header
                    if groups.isEmpty {
                        emptyForFilter
                    } else {
                        List {
                            ForEach(groups) { group in
                                row(for: group)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            }
                        }
                        .listStyle(.plain)
                        // 一覧の上を右へなぞると音源の一覧へ戻る
                        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
                    }
                }
            }
        }
        // 横から入ってくる間に後ろの画面が透けないよう、自前の下地を持つ
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("\(learned.count) / \(allGroups.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                TranslationToggle()
            }

            ProgressView(value: Double(learned.count), total: Double(max(allGroups.count, 1)))
                .tint(.accentColor)

            Picker("表示", selection: $filter) {
                Text("すべて").tag(Filter.all)
                Text("未習").tag(Filter.unlearned)
                Text("習得済み").tag(Filter.learned)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .opaqueBar(edges: .top)
        // 題名の帯を出していないので、ここでも戻る操作を受ける
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
    }

    private func row(for group: SubtitleGroup) -> some View {
        let isLearned = learned.contains(group.id)
        let lines = displayLines(of: group)

        return HStack(alignment: .top, spacing: 10) {
            // 丸印は状態の表示。押す場所はどこでもよいので、ここはただの絵にする
            Image(systemName: isLearned ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isLearned ? Color.accentColor : Color.secondary.opacity(0.5))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    Text(line.text)
                        .font(index == 0 ? .body : .subheadline)
                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // 大きさを変えるのは英文と訳だけ。印や見出しまで動くと画面が崩れる。
            .dynamicTypeSize(settings.textSize)
            .opacity(isLearned ? 0.45 : 1)
        }
        // 余白も含めて、行のどこを押しても印が入れ替わるようにする
        .contentShape(Rectangle())
        .onTapGesture { setLearned(group.id, !isLearned) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("phraseRow")
        .accessibilityHint(isLearned ? "押すと覚えた印を外します" : "押すと覚えた印を付けます")
    }

    private func displayLines(of group: SubtitleGroup) -> [TranscriptLine] {
        let lines = group.lines(in: cues)
        guard !settings.showTranslation else { return lines }
        let english = lines.filter { !$0.text.looksLikeTranslation }
        return english.isEmpty ? lines : english
    }

    // MARK: - 読み込みと保存

    private func load() {
        guard let url = library.subtitleURL(for: track) else { return }
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS)) ?? ""
        cues = SubtitleParser.parse(content)
        allGroups = cues.grouped()
        learned = library.learnedGroups(for: track.id, cueCount: cues.count)
    }

    private func setLearned(_ group: Int, _ value: Bool) {
        if value { learned.insert(group) } else { learned.remove(group) }
        library.setLearned(value, group: group, cueCount: cues.count, for: track.id)
        // 同じ音源を再生中なら、そちらの表示にも即座に反映する
        if player.currentTrackID == track.id {
            player.setLearned(value, group: group)
        }
    }

    // MARK: - 空の状態

    private var noSubtitle: some View {
        VStack(spacing: 14) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("字幕がありません")
                .font(.title3.weight(.semibold))
            Text("ライブラリでこの音源を長押しし、\n「字幕を追加」から読み込んでください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
    }

    private var emptyForFilter: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIcon)
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
    }

    private var emptyIcon: String {
        switch filter {
        case .learned: return "circle"
        default: return "checkmark.circle"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .learned: return "覚えた印を付けた項目はまだありません"
        default: return "すべて覚えた印が付いています"
        }
    }
}
