import SwiftUI

/// 一覧の最初の枠を、タイトルの帯のすぐ下から始める。
///
/// 標準の一覧・フォームは最初の節の上に大きな空きを取る。新しい iOS では
/// 正式な口で詰め、古い iOS では同じ見た目になるぶんだけ上へ寄せる。
/// タブごとに空きがばらつくと目につくので、どのタブもこれで揃える。
struct TightTop: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.top, 6, for: .scrollContent)
        } else {
            content.padding(.top, -16)
        }
    }
}

extension View {
    /// タイトルと中身の間の空きを詰める。
    func tightTop() -> some View { modifier(TightTop()) }
}
