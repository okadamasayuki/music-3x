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

/// 操作の帯。単色で塗り、必要なら画面の端まで伸ばす。
///
/// すりガラスは「後ろにあるもの」をぼかして写すため、画面が横から入ってくる
/// 途中で後ろの一覧が透ける。下地を敷いて重ねると今度は継ぎ目がスジに見えた。
/// 一枚の単色にして、どちらも起こらないようにする。
struct OpaqueBar: ViewModifier {
    /// 塗りを safe area の外まで伸ばす向き。伸ばさないと端に別色の帯が残る。
    var edges: Edge.Set

    func body(content: Content) -> some View {
        content.background(
            Color(.secondarySystemBackground).ignoresSafeArea(edges: edges)
        )
    }
}

extension View {
    func opaqueBar(edges: Edge.Set = []) -> some View {
        modifier(OpaqueBar(edges: edges))
    }
}
