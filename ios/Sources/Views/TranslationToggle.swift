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
            Text("訳")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(settings.showTranslation ? Color.white : Color.secondary)
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(settings.showTranslation
                              ? Color.accentColor
                              : Color.secondary.opacity(0.18))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.showTranslation ? "日本語訳を隠す" : "日本語訳を表示")
        .accessibilityIdentifier("translationToggle")
    }
}
