import SwiftUI

/// 音声を鳴らさずに、フレーズを見ながら覚えた印を付けるための画面。
/// プレイヤーと同じ字幕・同じ印を参照するので、どちらで付けても互いに反映される。
struct PhraseListView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: AppSettings

    private enum Filter: String, CaseIterable, Identifiable {
        case all, unlearned, learned
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "すべて"
            case .unlearned: return "未習"
            case .learned: return "習得済み"
            }
        }
    }

    @State private var filter: Filter = .all

    private var groups: [SubtitleGroup] {
        switch filter {
        case .all: return player.groups
        case .unlearned: return player.groups.filter { !player.learnedGroups.contains($0.id) }
        case .learned: return player.groups.filter { player.learnedGroups.contains($0.id) }
        }
    }

    var body: some View {
        Group {
            if player.groups.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("フレーズ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        VStack(spacing: 0) {
            header
            if groups.isEmpty {
                emptyForFilter
            } else {
                List {
                    ForEach(groups) { group in
                        row(for: group)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text(player.title.isEmpty ? "音源" : player.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(player.learnedGroups.count) / \(player.groups.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(player.learnedGroups.count),
                         total: Double(max(player.groups.count, 1)))
                .tint(.accentColor)

            Picker("表示", selection: $filter) {
                ForEach(Filter.allCases) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private func row(for group: SubtitleGroup) -> some View {
        let isLearned = player.learnedGroups.contains(group.id)
        let lines = displayLines(of: group)

        return Button {
            setLearned(group.id, !isLearned)
        } label: {
            HStack(alignment: .top, spacing: 12) {
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
                .opacity(isLearned ? 0.45 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lines.first?.text ?? "")
        .accessibilityValue(isLearned ? "覚えた" : "未習")
        .accessibilityHint("押すと覚えた印を切り替えます")
    }

    private func displayLines(of group: SubtitleGroup) -> [TranscriptLine] {
        let lines = group.lines(in: player.cues)
        guard !settings.showTranslation else { return lines }
        let english = lines.filter { !$0.text.looksLikeTranslation }
        return english.isEmpty ? lines : english
    }

    private func setLearned(_ group: Int, _ learned: Bool) {
        player.setLearned(learned, group: group)
        if let trackID = player.currentTrackID {
            library.setLearned(learned, group: group, cueCount: player.cues.count, for: trackID)
        }
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("フレーズがまだありません")
                .font(.title3.weight(.semibold))
            Text("ライブラリから字幕付きの音源を開くと、\nここに一覧が出ます。音声は流れません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var emptyForFilter: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .learned ? "circle" : "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text(filter == .learned ? "覚えた印を付けた項目はまだありません"
                                    : "すべて覚えた印が付いています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
