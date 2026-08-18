import AVFoundation
import Combine
import Foundation
import Speech

/// 改善メモを声で書き取るための聞き役。
///
/// VoiceCommands は英単語の合図を拾う専用なので、日本語の文章を書き取る
/// こちらは別に持つ。マイクは一つしかなく、同時に開くとぶつかるため、
/// 使う側でどちらか一方だけを動かすこと。
///
/// 認識は黙っていると勝手に締め切られるが、書き取りはそこで終わらせない。
/// 締め切られるたびに、そこまでの文を確定分へ積み上げて認識を組み直し、
/// 使い手がボタンで止めるまで聞き続ける。作業しながらの長い口述で、
/// 考え込んで黙っても書きかけが消えないようにするため。
final class Dictation: NSObject, ObservableObject {

    @Published private(set) var isRecording = false
    /// ここまでに聞き取れた文。確定分の後ろへ、いまの途中経過が足されていく。
    @Published private(set) var transcript = ""
    /// 許可が下りないなど、始められなかった理由。
    @Published private(set) var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 締め切られた区切りまでに確定した文。
    private var committed = ""
    /// いまの区切りで聞き取れている途中経過。
    private var partial = ""
    /// いまの区切りを聞き始めた時刻。始めてすぐ切れる失敗の連続を見分ける。
    private var segmentBegan = Date()
    /// 声も拾えないまますぐ切れた回数。認識そのものが不調だと組み直しても
    /// すぐ切れるので、続くようなら諦めて止める。
    private var quickDeaths = 0

    func start() {
        guard !isRecording else { return }
        problem = nil
        transcript = ""
        committed = ""
        partial = ""
        quickDeaths = 0
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
                        self?.begin()
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
        // 音の通り道を元に戻す。入れたままだと再生の音質が落ちる。
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        isRecording = false
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            problem = "この端末では日本語の音声認識が使えません。"
            return
        }
        do {
            // 再生中でも書き取れるよう playAndRecord にする。mode を .voiceChat に
            // するとエコー消去が働き、スピーカーで鳴っている教材の声を拾いにくくなる。
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            problem = "マイクを開けませんでした。(\(error.localizedDescription))"
            return
        }

        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }

        startSegment()

        engine.prepare()
        do {
            try engine.start()
        } catch {
            problem = "マイクを開けませんでした。(\(error.localizedDescription))"
            task?.cancel()
            task = nil
            request = nil
            return
        }
        isRecording = true
    }

    /// 一つの区切りの認識を始める。黙って締め切られるたびに組み直して呼ぶ。
    private func startSegment() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // メモの中身を外へ出さないため、できる端末では中だけで聞き取る。
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        self.request = request
        segmentBegan = Date()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
            DispatchQueue.main.async {
                // 止めた後や組み直した後にも古い区切りから声が届くことがある。
                // いまの区切りのものだけを受け取る。
                guard let self, let request, request === self.request else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if !self.partial.isEmpty { self.quickDeaths = 0 }
                    self.transcript = Self.join(self.committed, self.partial)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.segmentEnded()
                }
            }
        }
    }

    /// 区切りが締め切られた。文を確定分へ移し、続けられるなら組み直す。
    private func segmentEnded() {
        committed = Self.join(committed, partial)
        partial = ""
        transcript = committed
        task = nil
        request = nil

        // 使い手が止めた後なら、片付けは済んでいる
        guard isRecording else { return }

        // マイクが死んでいたら組み直しても聞こえない。文は残して止める。
        guard engine.isRunning, recognizer?.isAvailable == true else {
            problem = "聞き取りが途中で止まりました。ここまでの文は残っています。"
            stop()
            return
        }
        // 声も拾えないまますぐ切れるのが続くのは、認識そのものの不調
        if Date().timeIntervalSince(segmentBegan) < 1 {
            quickDeaths += 1
            if quickDeaths >= 3 {
                problem = "聞き取りが続けられませんでした。ここまでの文は残っています。"
                stop()
                return
            }
        }
        startSegment()
    }

    /// 区切りごとに聞き取れた文をつなぐ。前の区切りが句読点で終わっていれば
    /// そのまま続け、そうでなければ空白を挟んで一言の切れ目を残す。
    private static func join(_ head: String, _ tail: String) -> String {
        let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        if let last = head.last, "。、!?!?…".contains(last) { return head + tail }
        return head + " " + tail
    }
}
