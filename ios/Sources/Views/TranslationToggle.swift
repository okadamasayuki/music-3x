import SwiftUI

/// 日本語訳の表示を 1 タップで切り替えるボタン。
/// 記号では何のことか伝わりにくいので「訳」と文字で示し、
/// 消してある状態は斜線で分かるようにする。
struct TranslationToggle: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            settings.showTranslation.toggle()
        } label: {
            Label("訳", systemImage: settings.showTranslation ? "captions.bubble.fill" : "captions.bubble")
                .chipLabel(active: settings.showTranslation)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.showTranslation ? "日本語訳を隠す" : "日本語訳を表示")
        .accessibilityIdentifier("translationToggle")
    }
}
