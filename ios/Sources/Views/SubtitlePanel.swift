import SwiftUI

/// 再生位置に同期した字幕を大きく見せる領域。
struct SubtitlePanel: View {
    let cue: SubtitleCue?
    let hasSubtitles: Bool
    let onAddSubtitle: () -> Void

    var body: some View {
        ZStack {
            if !hasSubtitles {
                placeholder
            } else if let cue {
                Text(cue.text)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)
                    // キューが切り替わるたびに軽くフェードさせる
                    .id(cue.id)
                    .transition(.opacity)
                    .accessibilityIdentifier("subtitle")
            } else {
                Text("♪")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: cue?.id)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("字幕は読み込まれていません")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("字幕ファイルを追加", action: onAddSubtitle)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.bordered)
        }
    }
}
