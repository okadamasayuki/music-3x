import Foundation

/// アプリ全体の設定。端末に保存し、次回起動時も引き継ぐ。
final class AppSettings: ObservableObject {

    /// 音源を開いたときの再生速度
    @Published var defaultSpeed: Double {
        didSet { store.set(defaultSpeed, forKey: Keys.defaultSpeed) }
    }

    /// 送り・戻しボタン 1 回あたりの秒数
    @Published var skipInterval: Double {
        didSet { store.set(skipInterval, forKey: Keys.skipInterval) }
    }

    /// 覚えた印の付いた項目を再生時に飛ばすか
    @Published var skipLearned: Bool {
        didSet { store.set(skipLearned, forKey: Keys.skipLearned) }
    }

    /// 覚えた印の付いた項目を字幕の一覧から消すか
    @Published var hideLearned: Bool {
        didSet { store.set(hideLearned, forKey: Keys.hideLearned) }
    }

    /// 日本語訳を表示するか。伏せると、英文だけを見て意味を思い出す練習ができる。
    @Published var showTranslation: Bool {
        didSet { store.set(showTranslation, forKey: Keys.showTranslation) }
    }

    static let speedChoices: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4]
    static let skipChoices: [Double] = [5, 10, 15, 20, 30]
    static let speedRange: ClosedRange<Double> = 0.5...4.0

    private enum Keys {
        static let defaultSpeed = "defaultSpeed"
        static let skipInterval = "skipInterval"
        static let skipLearned = "skipLearned"
        static let hideLearned = "hideLearned"
        static let showTranslation = "showTranslation"
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        // 未設定のときは object(forKey:) が nil になるので、既定値と区別できる
        defaultSpeed = (store.object(forKey: Keys.defaultSpeed) as? Double) ?? 1.0
        skipInterval = (store.object(forKey: Keys.skipInterval) as? Double) ?? 10
        skipLearned = (store.object(forKey: Keys.skipLearned) as? Bool) ?? true
        hideLearned = (store.object(forKey: Keys.hideLearned) as? Bool) ?? false
        showTranslation = (store.object(forKey: Keys.showTranslation) as? Bool) ?? true
    }

    func resetToDefaults() {
        defaultSpeed = 1.0
        skipInterval = 10
        skipLearned = true
        hideLearned = false
        showTranslation = true
    }
}
