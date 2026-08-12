import SwiftUI

/// 字幕を 1 行 1 フレーズで並べ、再生位置に合わせて追従させる画面。
/// 項目ごとに「覚えた」印を付けられ、印の付いた項目は再生時に飛ばせる。
struct TranscriptView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    /// 覚えた印の変更を保存するために呼び出し側へ渡す
    var onToggleLearned: (Int, Bool) -> Void
    /// お気に入りの変更も同じく呼び出し側で保存する
    var onToggleFavorite: (Int, Bool) -> Void

    @State private var isFollowing = true

    /// 画面に出す項目。設定によっては覚えた分を伏せる。
    private var visibleGroups: [SubtitleGroup] {
        settings.hideLearned
            ? player.groups.filter { !player.learnedGroups.contains($0.id) }
            : player.groups
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if visibleGroups.isEmpty {
                    emptyNotice
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleGroups) { group in
                            GroupBlock(
                                group: group,
                                lines: displayLines(of: group),
                                textSize: settings.textSize,
                                // 項目が再生中なら、英文も訳もまとめて強調する
                                isPlaying: isPlaying(group),
                                isLearned: player.learnedGroups.contains(group.id),
                                isFavorite: player.favoriteGroups.contains(group.id),
                                onPlayLine: { line in
                                    guard let first = line.cueIndices.first,
                                          player.cues.indices.contains(first) else { return }
                                    player.seek(to: player.cues[first].start)
                                    player.play()
                                },
                                onToggleLearned: {
                                    onToggleLearned(group.id, !player.learnedGroups.contains(group.id))
                                },
                                onToggleFavorite: {
                                    onToggleFavorite(group.id, !player.favoriteGroups.contains(group.id))
                                }
                            )
                            .id(group.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isFollowing {
                    Button {
                        isFollowing = true
                        scroll(proxy, animated: true)
                    } label: {
                        Label("現在位置へ", systemImage: "location.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                    .padding(16)
                }
            }
            .onChange(of: player.currentGroupIndex) { _ in
                if isFollowing { scroll(proxy, animated: true) }
            }
            .onAppear { scroll(proxy, animated: false) }
            .simultaneousGesture(
                // 手で動かしたら追従を止める。読み返している最中に引き戻されると邪魔なため。
                DragGesture().onChanged { _ in isFollowing = false }
            )
        }
    }

    private var emptyNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text("すべて覚えた印が付いています")
                .font(.subheadline.weight(.medium))
            Text("設定で「覚えた項目を字幕から隠す」を切ると表示されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    /// 訳を伏せる設定なら、訳の行を落として英文だけを並べる。
    private func displayLines(of group: SubtitleGroup) -> [TranscriptLine] {
        let lines = group.lines(in: player.cues)
        guard !settings.showTranslation else { return lines }
        let english = lines.filter { !$0.text.looksLikeTranslation }
        // 訳しか無い項目まで消してしまわないよう、空になるなら元のまま出す
        return english.isEmpty ? lines : english
    }

    /// 字幕と字幕の間や、同じ英文の読み直しの合間でも強調を切らさない。
    /// 行ではなく項目を単位に見るので、項目の中にいる限り光ったままになる。
    private func isPlaying(_ group: SubtitleGroup) -> Bool {
        group.id == player.highlightedGroupIndex
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let index = player.currentGroupIndex else { return }
        // 伏せている項目へは飛べないので、表示中のものだけを対象にする
        guard visibleGroups.contains(where: { $0.id == index }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}

/// 教材の 1 項目分。数行の字幕と「覚えた」印をひとまとまりで扱う。
private struct GroupBlock: View {
    let group: SubtitleGroup
    /// 同じ文の読み直しはまとめてあるので、1 項目でも数行しか出ない
    let lines: [TranscriptLine]
    /// 英文と訳だけに効かせる文字の大きさ
    let textSize: DynamicTypeSize
    let isPlaying: Bool
    let isLearned: Bool
    let isFavorite: Bool
    let onPlayLine: (TranscriptLine) -> Void
    let onToggleLearned: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleLearned) {
                Image(systemName: isLearned ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isLearned ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(isLearned
                ? "\(group.id + 1) 番目の項目の覚えた印を外す"
                : "\(group.id + 1) 番目の項目を覚えた")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    CueRow(text: line.text, isCurrent: isPlaying, onPlay: { onPlayLine(line) })
                }
            }
            // 大きさを変えるのは英文と訳だけ。印や操作の類はそのまま。
            .dynamicTypeSize(textSize)
            .opacity(isLearned ? 0.4 : 1)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.subheadline)
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            .accessibilityLabel(isFavorite
                ? "\(group.id + 1) 番目の項目をお気に入りから外す"
                : "\(group.id + 1) 番目の項目をお気に入りに入れる")
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPlaying ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        // 再生中の項目を外から特定できるようにしておく(表示と音声のずれを検査するため)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isPlaying ? "currentGroup" : "group")
    }
}

/// 字幕 1 行。二度続けて押すと、その行から再生する。
/// 一度押しでは動かさない。読み返しでスクロールしている最中に
/// 触れただけで再生位置が飛ぶと邪魔になるため。
private struct CueRow: View {
    let text: String
    let isCurrent: Bool
    let onPlay: () -> Void

    var body: some View {
        Text(text)
            .font(.body)
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onPlay)
            // 画面を見ずに操作する場合のために、読み上げからは一度の操作で実行できるようにする
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("二回続けて押すと、ここから再生します")
            .accessibilityAction(named: "ここから再生", onPlay)
    }
}
