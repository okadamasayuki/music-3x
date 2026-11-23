import SwiftUI

/// プレイヤーと聞き取りテストで共通に使う、暗い紺の見た目。
/// 地は夜空のような紺、差し色は青緑の光。覚えた印は緑。
enum Night {
    static let cyan = Color(red: 0.35, green: 0.85, blue: 1.0)
    static let blue = Color(red: 0.30, green: 0.50, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.42, blue: 1.0)
    static let green = Color(red: 0.25, green: 0.85, blue: 0.55)
    static let greenDeep = Color(red: 0.10, green: 0.66, blue: 0.45)
    static let orange = Color(red: 1.0, green: 0.68, blue: 0.30)
    static let sky = Color(red: 0.035, green: 0.05, blue: 0.12)
    static let indigo = Color(red: 0.09, green: 0.10, blue: 0.26)
    /// 透けない札の地。字幕が下を流れても文字が透けないように不透明にしてある。
    static let card = Color(red: 0.11, green: 0.13, blue: 0.29)

    /// 再生ボタンや選んだ札に使う、青緑から青への光
    static var glow: LinearGradient {
        LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 暗い地と、画面の中ほどにぼんやり灯る光
struct NightBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Night.sky, Night.indigo], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Night.blue.opacity(0.30), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 320)
            RadialGradient(colors: [Night.violet.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 260)
        }
    }
}

/// うっすら透けるカード。下に文字が流れてこない所で使う。
struct GlassCard: View {
    var cornerRadius: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(GlassEdge(cornerRadius: cornerRadius))
    }
}

/// 上が明るく下が消える細い縁。カードに厚みを感じさせる。
struct GlassEdge: View {
    var cornerRadius: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
    }
}
