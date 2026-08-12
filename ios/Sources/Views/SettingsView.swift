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

            if settings.voiceControl {
                if let problem = voice.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    HStack {
                        Text(voice.isListening
                             ? (voice.echoCancelled ? "聞いています" : "聞いています(再生音を拾います)")
                             : "準備中")
                            .font(.footnote)
                            .foregroundStyle(voice.isListening
                                             ? (voice.echoCancelled ? Color.green : Color.orange)
                                             : Color.secondary)
                        Spacer()
                        Text(voice.lastHeard)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .accessibilityIdentifier("voiceHeard")
                    }
                    if !voice.lastMatched.isEmpty {
                        HStack {
                            Text(voice.lastMatchedBecameLearned ? "直前に付けた印" : "直前に外した印")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(voice.lastMatchedHeardAs == voice.lastMatched
                                 ? voice.lastMatched
                                 : "\(voice.lastMatched) ←「\(voice.lastMatchedHeardAs)」")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(voice.lastMatchedBecameLearned
                                                 ? Color.accentColor : Color.secondary)
                                .lineLimit(1)
                                .accessibilityIdentifier("voiceMatched")
                        }
                    }
                }
                Text("英単語を声に出すと、その単語の覚えた印が入れ替わります。"
                     + "付いていなければ付き、付いていれば外れます。"
                     + "同じ語が何か所にも出てくる場合は、どれか決められないので反応しません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
            expirySection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
