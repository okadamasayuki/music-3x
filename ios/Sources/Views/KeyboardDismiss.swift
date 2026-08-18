import SwiftUI
import UIKit

/// 入力欄の外を触ったらキーボードを下げる。
///
/// SwiftUI の onTapGesture を画面全体に掛けると、入力欄自身への触りも
/// 拾ってしまい、開いた矢先に閉じる。UIKit の認識器を窓に仕掛けて、
/// 入力欄への触りだけ除くとちょうどよくなる。
/// cancelsTouchesInView を切ってあるので、ボタンや行の反応はそのまま通る。
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { Installer.shared.install() }
            .onDisappear { Installer.shared.remove() }
    }

    final class Installer: NSObject, UIGestureRecognizerDelegate {
        static let shared = Installer()
        private var recognizer: UITapGestureRecognizer?

        func install() {
            guard recognizer == nil,
                  let window = UIApplication.shared.connectedScenes
                      .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                      .first else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
        }

        func remove() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }

        @objc private func dismiss() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        /// 入力欄そのものへの触りでは閉じない。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

extension View {
    /// この画面が出ている間、入力欄の外を触るとキーボードが下がる。
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}
