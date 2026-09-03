import SwiftUI
import UIKit

/// 日本語だけを見て英文を思い出す練習のタブ。音源を選んでから練習に入る。
///
/// 聞いて分かることと、日本語から言えることは別の段階なので、
/// ここの「できた」はライブラリの覚えた印とは別勘定で数える。
struct RecallListView: View {
    /// 練習画面を開く操作。画面の重なりは呼び出し側(RootView)が持つ。
    /// 画面遷移で出すと、戻るときにタブの帯の再表示が一拍遅れるため、
    /// プレイヤーと同じ「帯ごと覆う重ね画面」で開く。
    var onOpen: (UUID) -> Void

    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                emptyState
            } else {
                List {
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
/// タブの帯まで覆う重ね画面として開くが、見た目は画面遷移で開いた
/// ときと同じに組む(戻るボタン+中央の題名+カード型の一覧)。
/// 遷移そのものを使わないのは、戻るときにタブの帯の再表示が
/// 一拍遅れるため。見た目と仕組みは別々に選べる。
struct RecallPracticeView: View {
    let track: Track
    /// 左上の戻るボタン。なぞって戻すのと同じ道をたどる。
    var onClose: () -> Void = {}
    /// 戻るなぞり操作の進み具合。重なりを管理している側へ渡す。
    var onBackDragChanged: (CGFloat) -> Void = { _ in }
    var onBackDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

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
        VStack(spacing: 0) {
            header
            if visibleIndices.isEmpty {
                allDone
            } else {
                List {
                    Section {
                        ForEach(visibleIndices, id: \.self) { index in
                            row(index)
                        }
                    } header: {
                        Text("できた \(done.count) / \(groups.count)")
                    }
                }
                .listStyle(.insetGrouped)
                .dynamicTypeSize(settings.textSize)
                // 一覧の上を右へなぞると音源の一覧へ戻る
                .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
            }
        }
        // 引っ張って伸びた分も同じ下地で埋まるように、全体を一覧と同じ色にする
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: load)
    }

    /// 標準のナビゲーションバーと同じ据わりの帯。戻る・題名・絞り込み。
    private var header: some View {
        ZStack {
            Text(track.displayName)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 96)
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("英作")
                    }
                    .foregroundStyle(.tint)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("recallBack")
                Spacer()
                // できたものを隠すかどうか。いまの見え方を短い言葉で示す。
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
        .padding(.horizontal, 12)
        .frame(height: 44)
        .opaqueBar(edges: .top)
        // 帯の上でも戻るなぞりを受ける
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
    }

    /// 絞り込みで全部できているとき。空白のままだと壊れて見える。
    private var allDone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.green)
            Text("この教材はぜんぶできています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .backSwipe(onChanged: onBackDragChanged, onEnded: onBackDragEnded)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 答えの英文は、行を押したときだけ
                if revealed.contains(index) {
                    ForEach(Array(english.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tint)
                            .fixedSize(horizontal: false, vertical: true)
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
