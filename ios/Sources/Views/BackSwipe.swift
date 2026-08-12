import SwiftUI

/// 右へなぞって一覧へ戻す操作。プレイヤーとフレーズの全画面で共通に使う。
///
/// 画面自身をずらして追従させるので、移動量は画面に依存しない基準で測る。
/// 既定のまま(動く画面が基準)だと、ずらす→測り直すの繰り返しで震える。
struct BackSwipe: ViewModifier {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    /// 横向きの動きだと見極めがついたか。ついてから追従を始める。
    @State private var isActive = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onChanged { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    if !isActive {
                        // 縦スクロールと取り合わないよう、横が縦を上回ったときだけ拾う
                        guard horizontal > 12, horizontal > vertical * 1.4 else { return }
                        isActive = true
                    }
                    onChanged(max(0, horizontal))
                }
                .onEnded { value in
                    guard isActive else { return }
                    isActive = false
                    onEnded(max(0, value.translation.width),
                            max(0, value.predictedEndTranslation.width))
                }
        )
    }
}

extension View {
    func backSwipe(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat, CGFloat) -> Void
    ) -> some View {
        modifier(BackSwipe(onChanged: onChanged, onEnded: onEnded))
    }
}

/// すりガラスの帯。下に不透明な色を敷いてから重ねる。
///
/// すりガラスは「後ろにあるもの」をぼかして写すため、画面が横から入ってくる
/// 途中では、まだ後ろにいる一覧の画面が透けて残像のように見えてしまう。
/// 自前の下地を敷けば、いつでも自分の背後だけを写す。
struct OpaqueBar: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Color(.systemBackground)
                Rectangle().fill(.bar)
            }
        }
    }
}

extension View {
    func opaqueBar() -> some View { modifier(OpaqueBar()) }
}
