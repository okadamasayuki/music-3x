import AVFoundation
import Combine
import Foundation
import Speech

/// 聞きながら、英単語を口に出して覚えた印を付けるための聞き役。
///
/// 「覚えた」と合図を言わせる形も試したが、英語と日本語が混ざるうえ、
/// どの項目に付いたのか分かりにくい。教材の英単語をそのまま言ってもらい、
/// その単語の項目に印を付ける。
final class VoiceCommands: NSObject, ObservableObject {

    /// 実際にマイクを開けているか。設定を入れても許可が下りなければ false のまま。
    @Published private(set) var isListening = false
    /// 直近に聞き取った言葉。設定画面で反応を確かめるために出す。
    @Published private(set) var lastHeard = ""
    /// 直近に印を付けた単語と、実際に聞き取れた言い方。
    /// 少し違って聞こえても拾うので、何に化けたのかを見せる。
    @Published private(set) var lastMatched = ""
    @Published private(set) var lastMatchedHeardAs = ""
    /// 許可が下りなかった場合の説明。
    @Published private(set) var problem: String?
    /// 自分の再生音をマイクから差し引けているか。切れているとスピーカーでは
    /// 教材の声を拾ってしまうので、設定画面に出して知らせる。
    @Published private(set) var echoCancelled = false

    /// 言葉から項目番号を引くための表。音源が変わるたびに入れ替える。
    var vocabulary: [String: Int] = [:]

    /// 単語を聞き取ったときに呼ぶ。渡すのは項目番号。
    var onMatch: ((Int) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 同じ項目に続けて反応しないよう、項目ごとに間を置く。
    private var firedAt: [Int: Date] = [:]
    private let cooldown: TimeInterval = 3

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
        // 音の通り道を元に戻す。入れたままだと再生の音質が落ちる。
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        echoCancelled = false
        isListening = false
        lastHeard = ""
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            problem = "この端末では英語の音声認識が使えません。"
            return
        }
        do {
            // 鳴らしながら録るので playAndRecord にする。既定のままだと
            // マイクを開けた瞬間に再生が止まる。
            //
            // mode は .voiceChat にする。この形でだけエコー消去が働き、
            // スピーカーから出た教材の声をマイク入力から差し引ける。
            // イヤホン無しで使うにはこれが要る。
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
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
        // 自分が鳴らした音をマイク入力から差し引く。engine を動かす前に入れる。
        if !input.isVoiceProcessingEnabled {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                print("[VoiceCommands] エコー消去を入れられませんでした: \(error)")
            }
        }
        echoCancelled = input.isVoiceProcessingEnabled

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
                DispatchQueue.main.async {
                    self.lastHeard = text
                    self.match(in: text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                // 認識は一定時間で切れる。切れたら組み直して聞き続ける。
                DispatchQueue.main.async { self.restart() }
            }
        }
        isListening = true
    }

    // MARK: - 聞き取った言葉を項目に結び付ける

    /// 直前に照合した言葉。同じ言葉を何度も引き直さないために覚えておく。
    private var lastExamined: [String] = []

    private func match(in text: String) {
        guard !vocabulary.isEmpty else { return }
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map(String.init)
        guard !words.isEmpty else { return }

        // 途中経過は前の分も含めて届くので、末尾のいくつかだけを見る。
        // 二語のつながり(per capita など)も拾えるよう、続く 2 語も試す。
        let tail = Array(words.suffix(4))
        var candidates: [String] = []
        for i in tail.indices {
            if i + 1 < tail.count { candidates.append("\(tail[i]) \(tail[i+1])") }
            candidates.append(tail[i])
        }
        let fresh = candidates.filter { !lastExamined.contains($0) }
        lastExamined = candidates

        for spoken in fresh {
            guard let hit = lookup(spoken), canFire(hit.group) else { continue }
            firedAt[hit.group] = Date()
            lastMatched = hit.word
            lastMatchedHeardAs = spoken
            onMatch?(hit.group)
        }
    }

    /// 聞き取った言葉から項目を引く。そのまま無ければ、少し違う綴りも許す。
    ///
    /// 認識は "declare" を "declair" のように取り違えることがある。
    /// 語の長さに応じた範囲までのずれなら同じ語とみなす。ただし同じ距離に
    /// 複数の候補が並ぶときは決められないので諦める。
    private func lookup(_ spoken: String) -> (word: String, group: Int)? {
        if let group = vocabulary[spoken] { return (spoken, group) }

        let limit = Self.allowedSlack(for: spoken)
        guard limit > 0 else { return nil }

        let spokenChars = Array(spoken)
        var best: (word: String, group: Int, distance: Int)?
        var tiedAtBest = false

        for (word, group) in vocabulary {
            // 長さが離れすぎているものは計算するまでもない
            guard abs(word.count - spoken.count) <= limit else { continue }
            let distance = Self.editDistance(spokenChars, Array(word), limit: limit)
            guard distance <= limit else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (word, group, distance)
                    tiedAtBest = false
                } else if distance == current.distance, group != current.group {
                    tiedAtBest = true
                }
            } else {
                best = (word, group, distance)
            }
        }
        guard let best, !tiedAtBest else { return nil }
        return (best.word, best.group)
    }

    /// 語の長さごとに、どこまでのずれを許すか。
    private static func allowedSlack(for word: String) -> Int {
        switch word.count {
        case 0...3: return 0     // 短すぎる語は許すと取り違えが増える
        case 4...5: return 1
        case 6...8: return 2
        default: return 3
        }
    }

    /// 綴りの隔たり。limit を超えると分かった時点で打ち切る。
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j-1] + 1, previous[j-1] + cost)
                rowMin = Swift.min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private func canFire(_ group: Int) -> Bool {
        guard let at = firedAt[group] else { return true }
        return Date().timeIntervalSince(at) > cooldown
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

/// 声で指せない、どの項目にも結び付かない語。
private let spokenStopWords: Set<String> = [
    "the", "and", "for", "with", "that", "this", "from", "into", "his", "her", "its",
    "was", "were", "are", "have", "has", "had", "not", "you", "him", "she", "they",
    "them", "our", "your", "their", "who", "what", "when", "where", "why", "how",
    "one", "two", "all", "any", "out", "off", "over", "under", "about", "than",
    "there", "here", "some", "such", "very", "more", "most", "much", "many",
]

extension Array where Element == SubtitleGroup {
    /// 声で項目を指すための表を作る。
    ///
    /// 同じ語が複数の項目に出てくる場合は入れない。どちらに印を付けるか
    /// 決められないうえ、言い間違いで思わぬ項目に付いてしまうため。
    func spokenVocabulary(in cues: [SubtitleCue]) -> [String: Int] {
        var wholeLine: [String: Set<Int>] = [:]
        var singleWord: [String: Set<Int>] = [:]

        for (index, group) in enumerated() {
            let english = group.lines(in: cues).map(\.text).filter { !$0.looksLikeTranslation }
            for line in english {
                let words = line.lowercased()
                    .split(whereSeparator: { !$0.isLetter && $0 != "'" })
                    .map(String.init)
                guard !words.isEmpty else { continue }
                wholeLine[words.joined(separator: " "), default: []].insert(index)
                for word in words where word.count >= 3 && !spokenStopWords.contains(word) {
                    singleWord[word, default: []].insert(index)
                }
            }
        }

        var map: [String: Int] = [:]
        // 行まるごとの一致を先に入れる。単語だけの教材はこちらで足りる。
        for (key, indices) in wholeLine where indices.count == 1 {
            map[key] = indices.first
        }
        // 例文の教材では、その例文にしか出てこない語を手がかりにする。
        for (key, indices) in singleWord where indices.count == 1 && map[key] == nil {
            map[key] = indices.first
        }
        return map
    }
}
