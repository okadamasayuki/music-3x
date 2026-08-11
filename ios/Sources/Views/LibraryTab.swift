import SwiftUI

/// 一覧と再生画面の重なりを自前で管理する。
///
/// 標準の画面遷移は、上部の帯を隠すと戻るスワイプまで無効になってしまう。
/// ここでは一覧を実際に背後へ置いたまま再生画面を重ねるので、
/// なぞっている最中も一覧が見え、指を離せば元に戻せる。
struct LibraryTab: View {
    @EnvironmentObject private var library: LibraryStore

    /// 開いている音源。nil なら一覧だけ。
    @Binding var openedTrackID: UUID?

    /// 再生画面を右へずらしている量。0 なら開いた状態。
    @State private var dragX: CGFloat = 0

    private var openedTrack: Track? {
        openedTrackID.flatMap { id in library.tracks.first(where: { $0.id == id }) }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(max(dragX / width, 0), 1)   // 0=開いている 1=閉じきった

            ZStack(alignment: .leading) {
                NavigationStack {
                    LibraryView(onOpen: open)
                }
                // 奥の一覧はわずかに左へ寄せておき、戻すにつれて定位置へ返す
                .offset(x: openedTrack == nil ? 0 : -width * 0.22 * (1 - progress))
                .overlay(
                    Color.black
                        .opacity(openedTrack == nil ? 0 : 0.18 * (1 - progress))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                )

                if let track = openedTrack {
                    PlayerView(
                        track: track,
                        onBackDragChanged: { dragX = max(0, $0) },
                        onBackDragEnded: { translation, predicted in
                            finish(translation: translation, predicted: predicted, width: width)
                        }
                    )
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .offset(x: dragX)
                    .shadow(color: .black.opacity(openedTrack == nil ? 0 : 0.3), radius: 12, x: -6)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                }
            }
        }
    }

    private func open(_ id: UUID) {
        dragX = 0
        withAnimation(.easeOut(duration: 0.28)) { openedTrackID = id }
    }

    func close() {
        guard openedTrackID != nil else { return }
        withAnimation(.easeOut(duration: 0.24)) { openedTrackID = nil }
        dragX = 0
    }

    /// 指を離したとき、戻しきるか元へ返すかを決める。
    private func finish(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        let enough = translation > width * 0.3 || predicted > width * 0.6
        if enough {
            withAnimation(.easeOut(duration: 0.22)) { dragX = width }
            // ずれきってから実体を外す。先に外すと画面が一瞬飛んで見える。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                openedTrackID = nil
                dragX = 0
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragX = 0 }
        }
    }
}
