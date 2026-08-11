import SwiftUI

/// 2.0 は "2x"、2.5 は "2.5x" のように余分な小数を出さない。
enum SpeedFormatter {
    static func label(for speed: Double) -> String {
        let rounded = (speed * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return "\(Int(rounded.rounded()))x"
        }
        return String(format: "%.2gx", rounded)
    }
}

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
                    Text(SpeedFormatter.label(for: speed))
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

/// 速度の微調整スライダー。ボタンの刻みに無い値を選ぶときに使う。
struct SpeedFineSlider: View {
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: PlayerEngine.speedRange, step: 0.05)
            .accessibilityLabel("再生速度の微調整")
    }
}
