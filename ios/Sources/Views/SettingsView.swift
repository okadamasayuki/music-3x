import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var voice: VoiceCommands

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
        }
    }

    /// 声で印を付ける切り替え。反応しているかその場で分かるよう、
    /// 聞き取った言葉をそのまま出す。
    private var voiceSection: some View {
        Section {
            Toggle(isOn: $settings.voiceControl) {
                Text("声で覚えた印を付ける")
            }
            .accessibilityIdentifier("voiceControl")

            // 聞き取りの様子と説明はプレイヤー画面に出しているので、ここには置かない。
            // 許可が下りていないときだけ、理由が分からないと直しようがないので出す。
            if settings.voiceControl, let problem = voice.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// 改善メモの送り先。家の Mac のローカルホスト名とポートを書いておく。
    private var improveSection: some View {
        Section {
            TextField("ホスト名:ポート", text: $settings.improveHost)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("improveHost")
        } header: {
            Text("改善メモの送り先")
        } footer: {
            Text("家の Mac の名前(システム設定 › 一般 › 共有の「ローカルホスト名」)とポート。Mac 側で一度 mac/install.sh を実行しておくと、改善タブの項目をスワイプしたときに Claude Code が実装を始めます。")
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

            // 送り・戻しの秒数はここから外した。画面の送り戻しを前後の塊への
            // 移動に変えたので、秒数を決める場面が無くなったため。
            // ロック画面の 10 秒送りだけは既定値のまま使う。

            Section {
                Toggle(isOn: $settings.skipLearned) {
                    Text("覚えた項目をスキップ")
                }
                Toggle(isOn: $settings.hideLearned) {
                    Text("覚えた項目を字幕から隠す")
                }
            }
            voiceSection
            improveSection
            expirySection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
