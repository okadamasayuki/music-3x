import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                // プレイヤー画面と同じボタンとスライダーを使う
                SpeedPresetRow(selection: $settings.defaultSpeed)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                SpeedFineSlider(value: $settings.defaultSpeed)
            } header: {
                Text("既定の再生速度: \(SpeedFormatter.label(for: settings.defaultSpeed))")
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
            }

            Section {
                Toggle(isOn: $settings.skipLearned) {
                    Text("覚えた項目を飛ばす")
                }
                Toggle(isOn: $settings.hideLearned) {
                    Text("覚えた項目を字幕から隠す")
                }
            } header: {
                Text("覚えた項目")
            } footer: {
                Text("「飛ばす」は再生時に読み飛ばし、その分だけ全体の長さも短く表示します。"
                     + "「隠す」は字幕の一覧から消して、まだ覚えていない分だけを並べます。")
            }
        }
        .navigationTitle("")
    }
}
