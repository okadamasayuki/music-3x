import SwiftUI

/// 字幕を一覧で見て、任意の行から再生を始めるための画面。
struct CueListView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                cueList
                    .navigationTitle("字幕一覧")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { dismiss() }
                        }
                    }
                    .onAppear {
                        // 開いた瞬間に今しゃべっている行まで送る
                        if let index = player.currentCueIndex {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
            }
        }
    }

    private var cueList: some View {
        List {
            ForEach(Array(player.cues.enumerated()), id: \.element.id) { pair in
                let index = pair.offset
                let cue = pair.element

                Button {
                    player.jump(to: cue)
                    dismiss()
                } label: {
                    CueRow(cue: cue)
                }
                .listRowBackground(rowBackground(isCurrent: index == player.currentCueIndex))
                .id(index)
            }
        }
    }

    private func rowBackground(isCurrent: Bool) -> Color {
        isCurrent ? Color.accentColor.opacity(0.12) : Color.clear
    }
}

private struct CueRow: View {
    let cue: SubtitleCue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TimeFormatter.string(from: cue.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tint)
            Text(cue.text)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}
