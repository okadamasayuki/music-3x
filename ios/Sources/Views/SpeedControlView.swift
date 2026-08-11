import SwiftUI

struct SpeedControlView: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("再生速度")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Self.label(for: player.speed))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
            }

            SpeedPresetRow(selection: $player.speed)
            SpeedFineSlider(value: $player.speed)
        }
    }

    /// 2.0 は "2x"、2.5 は "2.5x" のように余分な小数を出さない。
    static func label(for speed: Double) -> String {
        let rounded = (speed * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return "\(Int(rounded.rounded()))x"
        }
        return String(format: "%.2gx", rounded)
    }
}
