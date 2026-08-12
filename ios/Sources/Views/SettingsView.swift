import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    /// 無料の開発者アカウントで入れたアプリは 7 日で起動できなくなる。
    /// いつ入れ直しが要るのか、開かなくても分かるようにしておく。
    @ViewBuilder
    private var expirySection: some View {
        Section {
            if let date = InstallExpiry.formattedDate, let days = InstallExpiry.daysRemaining {
                HStack {
                    Text("使える期限")
                    Spacer()
                    Text(date)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("残り")
                    Spacer()
                    Text(days == 0 ? "期限切れ" : "\(days) 日")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(days == 0 ? Color.red
                                         : days <= 2 ? Color.orange : Color.primary)
                }
            } else {
                HStack {
                    Text("使える期限")
                    Spacer()
                    Text("確認できません")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("この端末での利用")
        }
    }

    /// 文字の大きさ。決めた結果をその場で確かめられるよう、
    /// フレーズ一覧と同じ組み方の見本を下に添える。
    private var textSizeSection: some View {
        Section {
            Slider(
                value: Binding(
                    get: { Double(settings.textSizeStep) },
                    set: { settings.textSizeStep = Int($0.rounded()) }
                ),
                in: 0...Double(AppSettings.textSizes.count - 1),
                step: 1,
                label: { Text("文字の大きさ") },
                minimumValueLabel: { Text("A").font(.system(size: 13)) },
                maximumValueLabel: { Text("A").font(.system(size: 24)) }
            )
            .accessibilityIdentifier("textSizeSlider")

            VStack(alignment: .leading, spacing: 0) {
                Text("declare")
                    .font(.body)
                Text("を宣言する")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .dynamicTypeSize(settings.textSize)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("textSizeSample")
        } header: {
            Text("文字の大きさ: \(settings.textSizeLabel)")
        }
    }

    var body: some View {
        Form {
            textSizeSection

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
                    Text("覚えた項目をスキップ")
                }
                Toggle(isOn: $settings.hideLearned) {
                    Text("覚えた項目を字幕から隠す")
                }
            } header: {
                Text("覚えた項目")
            }
            expirySection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
