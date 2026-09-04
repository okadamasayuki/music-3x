import Foundation
import SwiftUI

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

    /// 声の合図で印を付けるか。入れている間だけマイクを開く。
    @Published var voiceControl: Bool {
        didSet { store.set(voiceControl, forKey: Keys.voiceControl) }
    }

    /// 最後まで行ったら先頭へ戻して流し続けるか。
    /// プレイヤー画面のボタンは外したので、ここで選ぶ。
    @Published var repeatTrack: Bool {
        didSet { store.set(repeatTrack, forKey: Keys.repeatTrack) }
    }

    /// 既定の音源(UUID の文字列、空なら無し)。アプリを開いたときに
    /// ミニプレイヤーへ載せておき、選んで開く手間を省く。
    @Published var defaultTrackID: String {
        didSet { store.set(defaultTrackID, forKey: Keys.defaultTrackID) }
    }

    /// 改善メモの送り先。家の Mac の「ローカルホスト名:ポート」。
    @Published var improveHost: String {
        didSet { store.set(improveHost, forKey: Keys.improveHost) }
    }

    /// 文字の大きさ。textSizes の何番目か。
    /// 端末側の文字サイズ設定に引きずられず、このアプリだけで決められるようにする。
    @Published var textSizeStep: Int {
        didSet { store.set(textSizeStep, forKey: Keys.textSizeStep) }
    }

    /// 既定の送り先。自宅の Mac mini。設定タブで書き換えられる。
    static let defaultImproveHost = "okadamasakinoMac-mini.local:8917"

    static let speedChoices: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4]
    static let skipChoices: [Double] = [5, 10, 15, 20, 30]
    static let speedRange: ClosedRange<Double> = 0.5...4.0

    /// スライダーの目盛り。端が細かすぎても使い道がないので、
    /// 実用になる範囲だけを並べてある。
    static let textSizes: [DynamicTypeSize] = [
        .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2,
    ]
    static let textSizeLabels = ["小", "やや小", "標準", "やや大", "大", "特大", "極大", "最大"]
    /// 既定は標準より二段階大きい「大」。単語を並べて眺める使い方では
    /// 端末の標準の大きさだと小さすぎるという求めによる。
    static let defaultTextSizeStep = 4

    private var clampedTextSizeStep: Int {
        min(max(textSizeStep, 0), Self.textSizes.count - 1)
    }

    var textSize: DynamicTypeSize { Self.textSizes[clampedTextSizeStep] }
    var textSizeLabel: String { Self.textSizeLabels[clampedTextSizeStep] }

    private enum Keys {
        static let defaultSpeed = "defaultSpeed"
        static let skipInterval = "skipInterval"
        static let skipLearned = "skipLearned"
        static let hideLearned = "hideLearned"
        static let showTranslation = "showTranslation"
        static let textSizeStep = "textSizeStep"
        static let voiceControl = "voiceControl"
        static let improveHost = "improveHost"
        static let repeatTrack = "repeatTrack"
        static let defaultTrackID = "defaultTrackID"
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
        textSizeStep = (store.object(forKey: Keys.textSizeStep) as? Int) ?? Self.defaultTextSizeStep
        // 既定では切っておく。断りなくマイクを開かないため。
        voiceControl = (store.object(forKey: Keys.voiceControl) as? Bool) ?? false
        improveHost = (store.object(forKey: Keys.improveHost) as? String) ?? Self.defaultImproveHost
        repeatTrack = (store.object(forKey: Keys.repeatTrack) as? Bool) ?? false
        defaultTrackID = (store.object(forKey: Keys.defaultTrackID) as? String) ?? ""
    }

    func resetToDefaults() {
        defaultSpeed = 1.0
        skipInterval = 10
        skipLearned = true
        hideLearned = false
        showTranslation = true
        textSizeStep = Self.defaultTextSizeStep
        voiceControl = false
        improveHost = Self.defaultImproveHost
        repeatTrack = false
        defaultTrackID = ""
    }
}
