import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

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
///
/// 別のアプリへ移っても書き取りは続く。電話などにマイクを取られたときも
/// 文を抱えたまま待ち、マイクが空きしだい聞き取りを取り戻す。調べ物を
/// 挟みながらの口述で、戻るたびに録り直しにならないようにするため。
final class Dictation: NSObject, ObservableObject {

    @Published private(set) var isRecording = false
    /// 電話などにマイクを取られ、取り戻すのを待っている間 true。
    @Published private(set) var isSuspended = false
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
    /// 中断と復帰の合図の聞き役。止めるときに外す。
    private var observers: [NSObjectProtocol] = []
    /// 最後に聞き取りが増えた時刻。止め忘れの見張りに使う。
    private var lastProgress = Date()
    /// 書き取りを始めた時刻。
    private var sessionBegan = Date()
    /// 止め忘れの見張り。マイクと認識は回しているだけで電池を食う。
    private var watchdog: Timer?

    func start() {
        guard !isRecording else { return }
        problem = nil
        transcript = ""
        committed = ""
        partial = ""
        quickDeaths = 0
        lastProgress = Date()
        sessionBegan = Date()
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
        watchdog?.invalidate()
        watchdog = nil
        removeObservers()
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
        isSuspended = false
        isRecording = false
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            problem = "この端末では日本語の音声認識が使えません。"
            return
        }
        recognizer.delegate = self
        do {
            try configureSession()
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
        installObservers()
        isSuspended = false
        isRecording = true
        startWatchdog()
    }

    /// 止め忘れの防波堤。
    ///
    /// 書き取りは完了ボタンまで聞き続ける約束だが、止め忘れたまま
    /// 放っておくと、マイクと認識が回り続けて電池が減り端末が熱くなる。
    /// 聞き取りがまったく増えないまま 10 分たつか、どれだけ増えていても
    /// 合計 1 時間を超えたら、文を残したまま自動で閉じる。
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            let idle = Date().timeIntervalSince(self.lastProgress)
            let total = Date().timeIntervalSince(self.sessionBegan)
            if idle > 10 * 60 || total > 60 * 60 {
                self.problem = "書き取りを自動で閉じました。ここまでの文は残っています。"
                self.stop()
            }
        }
    }

    /// 書き取り用にマイクの通り道を整える。始めるときと、中断から
    /// 取り戻すときの両方で使う。
    private func configureSession() throws {
        // 再生中でも書き取れるよう playAndRecord にする。mode を .voiceChat に
        // するとエコー消去が働き、スピーカーで鳴っている教材の声を拾いにくくなる。
        //
        // .mixWithOthers は、別のアプリで調べ物をしながら口述するため。
        // これが無いと、移った先のアプリが音を鳴らした瞬間にマイクを
        // 取り上げられ、書き取りが途切れる。
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetooth,
                                          .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
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
                    self.absorb(result.bestTranscription.formattedString)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.segmentEnded()
                }
            }
        }
    }

    /// 聞き取れている文を捨てて、聞き取りそのものは続ける。言い直したいとき用。
    ///
    /// いまの区切りは打ち切って組み直す。生かしたままだと、話しかけの
    /// 発話の途中経過がまた丸ごと届き、消したはずの文が戻ってくるため。
    func clearText() {
        committed = ""
        partial = ""
        transcript = ""
        guard isRecording, !isSuspended else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        startSegment()
    }

    /// 途中経過を取り込む。
    ///
    /// 認識は同じ区切りの中でも、発話の切れ目で仕切り直すことがある。
    /// そのとき途中経過は前触れなく短くなり、締め切りの合図も来ないため、
    /// 区切りの積み上げだけでは前の発話の文がそのまま消えていた。
    /// 大きく縮んだら仕切り直しとみなし、前の発話ぶんを確定分へ積んでから
    /// 新しい途中経過を受け取る。言い直しでも多少は縮むので、それとの
    /// 見分けとして、半分を切るほど縮んだときだけ仕切り直しと扱う。
    private func absorb(_ text: String) {
        if !partial.isEmpty, text.count < partial.count / 2, !partial.hasPrefix(text) {
            committed = Self.join(committed, partial)
        }
        partial = text
        if !partial.isEmpty { quickDeaths = 0 }
        let before = transcript
        transcript = Self.join(committed, partial)
        // 文が実際に増減したときだけ「進みあり」と数える。雑音では滅多に
        // 変わらないので、止め忘れの見張り(watchdog)がちゃんと働く。
        if transcript != before { lastProgress = Date() }
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
        // 中断の扱いは合図の聞き役がやっている。ここで組み直すと二重になる
        guard !isSuspended else { return }

        // マイクや認識を失っていたら、組み直しても聞こえない。完了までは
        // 諦めず、文を抱えたまま取り戻せる合図を待つ。
        guard engine.isRunning, recognizer?.isAvailable == true else {
            suspend()
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

    // MARK: - 中断と取り戻し

    /// 中断と復帰の合図に耳を立てる。完了ボタンまで聞き続けるための備え。
    private func installObservers() {
        removeObservers()
        let center = NotificationCenter.default
        // 電話や Siri、他アプリの割り込み
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.interruptionChanged(note)
        })
        // イヤホンの抜き差しなどで音の形が変わると engine は止まる。組み直して続ける
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.suspend()
            self.attemptResume()
        })
        // 中断の終わりの知らせが来ないまま使い手がこのアプリへ戻ることがある。
        // 戻ってきたのを機に取り戻しを試す
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.attemptResume()
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func interruptionChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            suspend()
        case .ended:
            // 「再開してよい」の印が付かない中断明けもある。マイクは書き取りの
            // 要なので、印によらず取り戻しを試す。だめなら次の合図を待つ
            attemptResume()
        @unknown default:
            break
        }
    }

    /// マイクを取られた。ここまでの文を確定分へ移して認識を畳み、
    /// 取り戻せる合図が来るまで待つ。使い手から見れば書き取りは続いたまま。
    private func suspend() {
        guard isRecording, !isSuspended else { return }
        isSuspended = true
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        committed = Self.join(committed, partial)
        partial = ""
        transcript = committed
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// 中断からの取り戻し。まだマイクが空いていなければ何もせず、次の合図を待つ。
    private func attemptResume() {
        guard isRecording, isSuspended else { return }
        guard recognizer?.isAvailable == true else { return }
        do {
            try configureSession()
        } catch {
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
            task?.cancel()
            task = nil
            request = nil
            input.removeTap(onBus: 0)
            return
        }
        quickDeaths = 0
        isSuspended = false
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

extension Dictation: SFSpeechRecognizerDelegate {
    /// 認識が使えない時間を挟んでも、戻りしだい聞き取りを取り戻す。
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard available else { return }
        DispatchQueue.main.async { [weak self] in
            self?.attemptResume()
        }
    }
}
