import SwiftUI

/// 速度をワンタップで選ぶボタンの並び。
/// プレイヤーと設定の両方で使うので、見た目が食い違わないよう部品にしてある。
struct SpeedPresetRow: View {
    @Binding var selection: Double
    var choices: [Double] = PlayerEngine.presetSpeeds

    var body: some View {
        HStack(spacing: 8) {
            ForEach(choices, id: \.self) { speed in
                let isActive = abs(selection - speed) < 0.001
                Button {
                    selection = speed
                } label: {
                    Text(SpeedControlView.label(for: speed))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(isActive ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 速度の微調整スライダー。こちらも両方の画面で同じものを使う。
struct SpeedFineSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tortoise").foregroundStyle(.secondary)
            Slider(value: $value, in: PlayerEngine.speedRange, step: 0.05)
            Image(systemName: "hare").foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}
