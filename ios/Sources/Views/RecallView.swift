import SwiftUI
import UIKit

/// 日本語だけを見て英文を思い出す練習のタブ。音源を選んでから練習に入る。
///
/// 聞いて分かることと、日本語から言えることは別の段階なので、
/// ここの「できた」はライブラリの覚えた印とは別勘定で数える。
struct RecallListView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(library.tracks) { track in
                            NavigationLink {
                                RecallPracticeView(track: track)
                            } label: {
                                Text(track.displayName)
                                    .font(.body)
                                    .lineLimit(2)
                                    .padding(.vertical, 8)
                            }
                            .accessibilityIdentifier("recallTrackRow")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tightTop()
            }
        }
        .navigationTitle("英作")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("音源がまだありません")
                .font(.title3.weight(.semibold))
            Text("ライブラリに字幕付きの音源を入れると、\n日本語から英文を思い出す練習ができます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

/// 練習の本体。日本語だけが並び、行を押すとその英文が現れる。
struct RecallPracticeView: View {
    let track: Track

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var cues: [SubtitleCue] = []
    @State private var groups: [SubtitleGroup] = []
    /// 「できた」の付いた項目。ライブラリの覚えた印とは別に保存する。
    @State private var done: Set<Int> = []
    /// いま英文を見せている項目。画面を離れると閉じる(練習なので)。
    @State private var revealed: Set<Int> = []
    /// できたものを隠して、まだの項目だけを出すか。次回も同じ見え方で開く。
    @AppStorage("recallHideDone") private var hideDone = false

    /// いま画面に出す項目。絞り込み中は、できた印の付いていないものだけ。
    private var visibleIndices: [Int] {
        groups.indices.filter { !hideDone || !done.contains($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(visibleIndices, id: \.self) { index in
                    row(index)
                }
            } header: {
                HStack {
                    Text("できた \(done.count) / \(groups.count)")
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
        .tightTop()
        .dynamicTypeSize(settings.textSize)
        .navigationTitle(track.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // 練習中はタブの帯を隠して画面を広く使う。プレイヤー画面と同じ感覚。
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // できたものを隠すかどうか。いまの見え方を短い言葉で示す。
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    hideDone.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hideDone ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                            .font(.footnote.weight(.semibold))
                        Text(hideDone ? "まだだけ" : "すべて")
                            .font(.footnote)
                    }
                    .foregroundStyle(hideDone ? Color.accentColor : Color.secondary)
                }
                .accessibilityLabel(hideDone ? "すべて表示する" : "できたものを隠す")
                .accessibilityIdentifier("recallFilter")
            }
        }
        .onAppear(perform: load)
    }

    private func row(_ index: Int) -> some View {
        let lines = groups[index].lines(in: cues).map(\.text)
        let japanese = lines.filter { $0.looksLikeTranslation }
        let english = lines.filter { !$0.looksLikeTranslation }
        let isDone = done.contains(index)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // できた印。行のタップ(英文の表示)と役目がぶつからないよう、
            // 丸だけを独立したボタンにする。
            Button {
                toggleDone(index)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "できた印を外す" : "できた印を付ける")

            VStack(alignment: .leading, spacing: 3) {
                // 問題は日本語。訳が無い項目は、仕方なくある行をそのまま出す
                ForEach(Array((japanese.isEmpty ? lines : japanese).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.body)
                }
                // 答えの英文は、行を押したときだけ
                if revealed.contains(index) {
                    ForEach(Array(english.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 押すたびに英文を出したり隠したりする
            if revealed.contains(index) {
                revealed.remove(index)
            } else {
                revealed.insert(index)
            }
        }
        .accessibilityIdentifier("recallRow")
    }

    private func toggleDone(_ index: Int) {
        let mark = !done.contains(index)
        if mark { done.insert(index) } else { done.remove(index) }
        library.setRecallDone(mark, group: index, cueCount: cues.count, for: track.id)
        UIImpactFeedbackGenerator(style: mark ? .medium : .soft).impactOccurred()
    }

    private func load() {
        guard let url = library.subtitleURL(for: track) else { return }
        // 字幕ファイルの文字コードは UTF-8 とは限らないため、失敗したら Shift_JIS を試す
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS))
            ?? ""
        cues = SubtitleParser.parse(content)
        groups = cues.grouped()
        done = library.recallDoneGroups(for: track.id, cueCount: cues.count)
    }
}
