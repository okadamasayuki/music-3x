#if targetEnvironment(simulator)
import Foundation

/// シミュレータの自動検証から画面を操作するための合図の受け口。
///
/// Mac 側から `xcrun simctl spawn <端末> notifyutil -p <名前>` で届く。
/// URL スキームは開くたびに確認ダイアログが出て自動化に使えないため、
/// こちらの仕組みを使う。実機向けのビルドには一行も含まれない。
enum TestSignals {

    private static var handler: ((String) -> Void)?

    static func install(_ handler: @escaping (String) -> Void) {
        Self.handler = handler
        let names = ["music3x.recall.open", "music3x.recall.back"]
            + (0..<10).map { "music3x.recall.reveal.\($0)" }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, _, name, _, _ in
            guard let raw = name?.rawValue else { return }
            let value = raw as String
            DispatchQueue.main.async { TestSignals.handler?(value) }
        }
        for name in names {
            CFNotificationCenterAddObserver(center, nil, callback, name as CFString, nil, .deliverImmediately)
        }
    }
}
#endif
