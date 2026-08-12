import AVFoundation
import Combine
import Foundation
import Speech

/// 聞きながら声で印を付けるための聞き役。
///
/// 単語名は言わせない。「覚えた」「お気に入り」のような短い合図だけを拾い、
/// そのときに流れている項目へ印を付ける。単語名まで聞き取ろうとすると、
/// 英語と日本語が混ざるうえ、教材の音そのものを拾って誤って動くため。
final class VoiceCommands: NSObject, ObservableObject {

    enum Command: Equatable {
        case learned      // 覚えた
        case favorite     // お気に入り
    }

    /// 実際にマイクを開けているか。設定を入れても許可が下りなければ false のまま。
    @Published private(set) var isListening = false
    /// 直近に聞き取った言葉。設定画面で反応を確かめるために出す。
    @Published private(set) var lastHeard = ""
    /// 許可が下りなかった場合の説明。
    @Published private(set) var problem: String?

    /// 合図を聞き取ったときに呼ぶ。
    var onCommand: ((Command) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 同じ言葉で二重に反応しないよう、一度反応したら少し間を置く。
    private var lastFiredAt = Date.distantPast
    private let cooldown: TimeInterval = 1.5

    // MARK: - 合図の言葉

    /// 認識のゆらぎを見込んで、言い方の候補を並べておく。
    private static let learnedWords = ["覚えた", "おぼえた", "覚えました", "オッケー", "OK"]
    private static let favoriteWords = ["お気に入り", "おきにいり", "気に入り", "スター", "star"]

    private func command(in text: String) -> Command? {
        // 後から言った合図を優先したいので、末尾に近いものを採る
        let learnedAt = Self.learnedWords.compactMap { text.range(of: $0)?.upperBound }.max()
        let favoriteAt = Self.favoriteWords.compactMap { text.range(of: $0)?.upperBound }.max()
        switch (learnedAt, favoriteAt) {
        case (nil, nil): return nil
        case (let l?, nil): _ = l; return .learned
        case (nil, let f?): _ = f; return .favorite
        case (let l?, let f?): return l >= f ? .learned : .favorite
        }
    }

    // MARK: - 開始と停止

    func start() {
        guard !isListening else { return }
        problem = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.problem = "音声認識の許可が下りていません。設定アプリから許可してください。"
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self?.problem = "マイクの許可が下りていません。設定アプリから許可してください。"
                            return
                        }
                        self?.beginSession()
                    }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isListening = false
        lastHeard = ""
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            problem = "この端末では日本語の音声認識が使えません。"
            return
        }
        do {
            // 鳴らしながら録るので playAndRecord にする。既定のままだと
            // マイクを開けた瞬間に再生が止まる。
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            problem = "マイクを開けませんでした。(\(error.localizedDescription))"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端末の中だけで聞き取る。教材の中身を外へ出さないため。
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            problem = "マイクを開けませんでした。(\(error.localizedDescription))"
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.lastHeard = text }
                if let command = self.command(in: text) {
                    DispatchQueue.main.async { self.fire(command) }
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                // 認識は一定時間で切れる。切れたら組み直して聞き続ける。
                DispatchQueue.main.async { self.restart() }
            }
        }
        isListening = true
    }

    private func fire(_ command: Command) {
        guard Date().timeIntervalSince(lastFiredAt) > cooldown else { return }
        lastFiredAt = Date()
        onCommand?(command)
        // 同じ言葉を拾い続けないよう、聞き取りを組み直す
        restart()
    }

    private func restart() {
        guard isListening else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isListening = false
        // 間を置かずに組み直すと失敗するので、少し待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.beginSession()
        }
    }
}
