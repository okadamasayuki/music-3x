import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("再生速度", selection: $settings.defaultSpeed) {
                    ForEach(AppSettings.speedChoices, id: \.self) { speed in
                        Text(SpeedControlView.label(for: speed)).tag(speed)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: $settings.defaultSpeed, in: AppSettings.speedRange, step: 0.05)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                }
                .font(.footnote)
            } header: {
                Text("既定の再生速度")
            } footer: {
                Text("音源を開いたときの速度です。現在 \(SpeedControlView.label(for: settings.defaultSpeed))。"
                     + "再生中はプレイヤー画面でいつでも変えられます。")
            }

            Section {
                Picker("送り・戻しの秒数", selection: $settings.skipInterval) {
                    ForEach(AppSettings.skipChoices, id: \.self) { s in
                        Text("\(Int(s)) 秒").tag(s)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("送り・戻し")
            } footer: {
                Text("プレイヤーのボタンと、ロック画面の送り・戻しに反映されます。")
            }

            Section {
                Toggle(isOn: $settings.skipLearned) {
                    Text("覚えた項目を飛ばす")
                }
            } footer: {
                Text("覚えた印を付けた項目を再生時に読み飛ばし、その分だけ全体の長さも短く表示します。")
            }

            Section {
                Button("設定を初期状態に戻す", role: .destructive) {
                    settings.resetToDefaults()
                }
            }
        }
        .navigationTitle("設定")
    }
}
