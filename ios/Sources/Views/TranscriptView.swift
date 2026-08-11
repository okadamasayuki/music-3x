import SwiftUI

/// 字幕を 1 行 1 フレーズで並べ、再生位置に合わせて追従させる画面。
/// 項目ごとに「覚えた」印を付けられ、印の付いた項目は再生時に飛ばせる。
struct TranscriptView: View {
    @EnvironmentObject private var player: PlayerEngine

    /// 覚えた印の変更を保存するために呼び出し側へ渡す
    var onToggleLearned: (Int, Bool) -> Void

    @State private var isFollowing = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(player.groups) { group in
                        GroupBlock(
                            group: group,
                            cues: cues(of: group),
                            currentCueIndex: player.currentCueIndex,
                            isLearned: player.learnedGroups.contains(group.id),
                            onTapCue: { player.seek(to: $0.start) },
                            onToggleLearned: { onToggleLearned(group.id, !player.learnedGroups.contains(group.id)) }
                        )
                        .id(group.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

    private func cues(of group: SubtitleGroup) -> [(index: Int, cue: SubtitleCue)] {
        group.range.compactMap { i in
            player.cues.indices.contains(i) ? (i, player.cues[i]) : nil
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let index = player.currentGroupIndex else { return }
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
    let cues: [(index: Int, cue: SubtitleCue)]
    let currentCueIndex: Int?
    let isLearned: Bool
    let onTapCue: (SubtitleCue) -> Void
    let onToggleLearned: () -> Void

    private var isCurrent: Bool {
        guard let i = currentCueIndex else { return false }
        return group.range.contains(i)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleLearned) {
                Image(systemName: isLearned ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isLearned ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(isLearned
                ? "\(group.id + 1) 番目の項目の覚えた印を外す"
                : "\(group.id + 1) 番目の項目を覚えた")

            VStack(alignment: .leading, spacing: 3) {
                ForEach(cues, id: \.index) { pair in
                    CueRow(
                        text: pair.cue.text,
                        isCurrent: pair.index == currentCueIndex,
                        onTap: { onTapCue(pair.cue) }
                    )
                }
            }
        }
        .opacity(isLearned ? 0.4 : 1)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.secondary.opacity(0.08) : Color.clear)
        )
    }
}

/// 字幕 1 行。押すとその位置から再生する。
private struct CueRow: View {
    let text: String
    let isCurrent: Bool
    let onTap: () -> Void

    private var background: Color {
        isCurrent ? Color.accentColor.opacity(0.15) : Color.clear
    }

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.body)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
        }
        .buttonStyle(.plain)
    }
}
