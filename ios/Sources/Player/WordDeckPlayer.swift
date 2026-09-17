import AVFoundation
import Combine
import MediaPlayer

/// 単語帳を「英語→日本語→英語」などの順で 1 語ずつ鳴らすプレイヤー。
/// 音源は単語ごとに分かれているので、再生順・リピート・間・速さを
/// 設定で自由に組める。既存の 1 本 mp3 プレイヤー(PlayerEngine)とは別立て。
final class WordDeckPlayer: NSObject, ObservableObject {

    // MARK: - 公開状態
    @Published private(set) var deck: WordDeck?
    @Published private(set) var index: Int = 0          // いま出している単語(deck.words の添字)
    @Published private(set) var isPlaying = false
    @Published private(set) var currentKind: String = "en"   // いま鳴らしている種類 en/ja

    var currentCard: WordCard? {
        guard let deck, deck.words.indices.contains(index) else { return nil }
        return deck.words[index]
    }

    // MARK: - 設定(端末に保存)
    /// 1 語あたりの再生順。"en"/"ja" の並び。例: 英→日→英。
    @Published var order: [String] { didSet { UserDefaults.standard.set(order.joined(separator: ","), forKey: "wd.order") } }
    /// 語の中の音と音の間(秒)
    @Published var gap: Double { didSet { UserDefaults.standard.set(gap, forKey: "wd.gap") } }
    /// 次の単語へ移るときの間(秒)
    @Published var wordGap: Double { didSet { UserDefaults.standard.set(wordGap, forKey: "wd.wordGap") } }
    /// 再生速度
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "wd.speed"); player?.rate = Float(speed) } }
    /// 最後まで行ったら先頭へ戻して流し続けるか
    @Published var loop: Bool { didSet { UserDefaults.standard.set(loop, forKey: "wd.loop") } }
    /// 覚えた印の付いた単語を再生で飛ばすか
    @Published var skipLearned: Bool { didSet { UserDefaults.standard.set(skipLearned, forKey: "wd.skipLearned") } }

    /// いまのデッキで「覚えた」印の付いている単語番号
    @Published private(set) var learned: Set<Int> = []

    private func learnedKey(_ deckID: String) -> String { "wd.learned.\(deckID)" }
    func isLearned(_ num: Int) -> Bool { learned.contains(num) }
    /// 覚えた印を付け外しする
    func toggleLearned(_ num: Int) {
        if learned.contains(num) { learned.remove(num) } else { learned.insert(num) }
        if let id = deck?.id {
            UserDefaults.standard.set(Array(learned), forKey: learnedKey(id))
        }
    }

    // MARK: - 内部
    private var player: AVAudioPlayer?
    private var step = 0                    // order の何番目か
    private var pending: DispatchWorkItem?
    private var token = 0                   // 途中での割り込み(次へ/停止)を無効化する印

    override init() {
        let savedOrder = (UserDefaults.standard.string(forKey: "wd.order") ?? "en,ja,en")
            .split(separator: ",").map(String.init).filter { $0 == "en" || $0 == "ja" }
        order = savedOrder.isEmpty ? ["en", "ja", "en"] : savedOrder
        let d = UserDefaults.standard
        gap = d.object(forKey: "wd.gap") as? Double ?? 0.35
        wordGap = d.object(forKey: "wd.wordGap") as? Double ?? 0.7
        speed = d.object(forKey: "wd.speed") as? Double ?? 1.0
        loop = d.object(forKey: "wd.loop") as? Bool ?? true
        skipLearned = d.object(forKey: "wd.skipLearned") as? Bool ?? true
        super.init()
        setupRemoteCommands()
    }

    // MARK: - 読み込み・再生制御

    func load(_ deck: WordDeck, startAt: Int = 0) {
        stop()
        self.deck = deck
        let saved = UserDefaults.standard.array(forKey: learnedKey(deck.id)) as? [Int] ?? []
        learned = Set(saved)
        index = deck.words.indices.contains(startAt) ? startAt : 0
        step = 0
        updateNowPlaying()
    }

    /// skipLearned が入っているとき、覚えた語を飛ばして次に鳴らせる添字を返す。
    /// 全部覚えていたら nil。
    private func playableIndex(from start: Int, forward: Bool) -> Int? {
        guard let deck, !deck.words.isEmpty else { return nil }
        if !skipLearned { return deck.words.indices.contains(start) ? start : nil }
        let n = deck.words.count
        var i = start
        for _ in 0..<n {
            if i < 0 { if loop { i = n - 1 } else { return nil } }
            if i >= n { if loop { i = 0 } else { return nil } }
            if !learned.contains(deck.words[i].num) { return i }
            i += forward ? 1 : -1
        }
        return nil   // 全部覚えた
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let deck, !deck.words.isEmpty else { return }
        activateSession()
        // 今の単語が覚えた印なら、飛ばして次の対象から始める
        if let i = playableIndex(from: index, forward: true) { index = i } else { return }
        isPlaying = true
        playCurrentStep()
    }

    func pause() {
        isPlaying = false
        token &+= 1
        pending?.cancel(); pending = nil
        player?.pause()
        updateNowPlaying()
    }

    func stop() {
        isPlaying = false
        token &+= 1
        pending?.cancel(); pending = nil
        player?.stop(); player = nil
    }

    /// 次の単語の頭から(覚えた印は飛ばす)
    func nextWord() {
        guard let deck else { return }
        token &+= 1
        pending?.cancel()
        step = 0
        if let i = playableIndex(from: index + 1, forward: true) { index = i }
        else { index = min(index + 1, deck.words.count - 1) }
        if isPlaying { playCurrentStep() } else { updateNowPlaying() }
    }

    /// 前の単語の頭から(覚えた印は飛ばす)
    func prevWord() {
        token &+= 1
        pending?.cancel()
        step = 0
        if let i = playableIndex(from: index - 1, forward: false) { index = i }
        else { index = max(index - 1, 0) }
        if isPlaying { playCurrentStep() } else { updateNowPlaying() }
    }

    /// 一覧から特定の単語へ飛ぶ
    func jump(to i: Int) {
        guard let deck, deck.words.indices.contains(i) else { return }
        token &+= 1
        pending?.cancel()
        step = 0
        index = i
        if isPlaying { playCurrentStep() } else { updateNowPlaying() }
    }

    // MARK: - 中身

    private func playCurrentStep() {
        guard isPlaying, let deck, deck.words.indices.contains(index) else { return }
        guard order.indices.contains(step) else { advanceWord(); return }
        let card = deck.words[index]
        let kind = order[step]
        currentKind = kind
        let url = deck.audioURL(kind == "ja" ? card.jaAudio : card.enAudio)
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.enableRate = true
            p.rate = Float(speed)
            p.prepareToPlay()
            player = p
            p.play()
            updateNowPlaying()
        } catch {
            // 音声が欠けていても止まらず次へ
            scheduleNext(after: 0.05)
        }
    }

    /// 今の音が鳴り終わったら、間をおいて次のステップ/単語へ
    private func scheduleNext(after delay: Double) {
        let my = token
        let work = DispatchWorkItem { [weak self] in
            guard let self, my == self.token, self.isPlaying else { return }
            self.step += 1
            if self.step >= self.order.count {
                self.step = 0
                self.advanceWord()
            } else {
                self.playCurrentStep()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func advanceWord() {
        guard deck != nil else { return }
        if let i = playableIndex(from: index + 1, forward: true) {
            // loop=false で末尾を越えたら playableIndex は nil を返すので、
            // ここに来るのは「次に鳴らす対象がある」ときだけ
            if i <= index && !loop { pause(); return }
            index = i
            playCurrentStep()
        } else {
            pause()
        }
    }

    // MARK: - セッション・ロック画面

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.nextWord(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prevWord(); return .success }
    }

    private func updateNowPlaying() {
        guard let card = currentCard, let deck else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: card.en,
            MPMediaItemPropertyArtist: card.ja,
            MPMediaItemPropertyAlbumTitle: deck.name,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
        ]
        info[MPMediaItemPropertyAlbumTrackCount] = deck.words.count
        info[MPMediaItemPropertyAlbumTrackNumber] = index + 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension WordDeckPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard isPlaying else { return }
        // 語の中の最後の音なら wordGap、それ以外は gap
        let isLastStepOfWord = (step + 1 >= order.count)
        scheduleNext(after: isLastStepOfWord ? wordGap : gap)
    }
}
