import SwiftUI

struct SpeedControlView: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("再生速度")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Self.label(for: player.speed))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
            }

            presetRow

            HStack(spacing: 10) {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $player.speed,
                    in: PlayerEngine.speedRange,
                    step: 0.05
                )
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            Toggle(isOn: $player.preservesPitch) {
                Label("音程を維持", systemImage: "waveform.path")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            // 伸ばし方の方式で声の聞こえ方が変わるので、再生しながら比べられるようにする
            if player.preservesPitch {
                Picker("音の伸ばし方", selection: $player.stretchMode) {
                    ForEach(StretchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(PlayerEngine.presetSpeeds, id: \.self) { speed in
                let isActive = abs(player.speed - speed) < 0.001
                Button {
                    player.speed = speed
                } label: {
                    Text(Self.label(for: speed))
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

    /// 2.0 は "2x"、2.5 は "2.5x" のように余分な小数を出さない。
    static func label(for speed: Double) -> String {
        let rounded = (speed * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return "\(Int(rounded.rounded()))x"
        }
        return String(format: "%.2gx", rounded)
    }
}
