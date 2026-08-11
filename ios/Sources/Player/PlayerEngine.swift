import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// AVPlayer をラップした再生エンジン。
/// 倍速・字幕同期・ロック画面操作・バックグラウンド再生をここで面倒を見る。
final class PlayerEngine: ObservableObject {

    /// ワンタップで選べる速度。Web 版の 1x/2x/3x/4x に半段刻みを足したもの。
    static let presetSpeeds: [Double] = [1, 1.5, 2, 2.5, 3, 4]
    static let speedRange: ClosedRange<Double> = 0.5...4.0

    /// 送り・戻し 1 回あたりの秒数。設定から変えられる。
    @Published var skipInterval: Double = 10 {
        didSet { updateRemoteSkipIntervals() }
    }

    /// ロック画面に訳を出すか。画面内の一覧と揃える。
    @Published var showsTranslation: Bool = true {
        didSet {
            artworkCacheKey = nil
            updateNowPlayingInfo()
        }
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isReady = false
    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var title: String = ""

    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var currentCueIndex: Int?

    /// 字幕を「教材の 1 項目」単位に束ねたもの。覚えた分を飛ばす単位でもある。
    @Published private(set) var groups: [SubtitleGroup] = []
    @Published private(set) var currentGroupIndex: Int?

    /// 強調しておく項目。字幕と字幕の間や読み直しの合間でも消えないよう、
    /// 項目から外れている間は直前の項目を保持する。
    @Published private(set) var highlightedGroupIndex: Int?
    @Published var learnedGroups: Set<Int> = []
    @Published var skipLearned: Bool = true {
        didSet { rebuildSkippedRanges() }
    }

    @Published var speed: Double = 1.0 {
        didSet { applyRate() }
    }


    /// 再生位置が変わるたびに呼ばれる。呼び出し側で保存に使う。
    var onPositionChange: ((UUID, Double) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var isScrubbing = false

    var currentCue: SubtitleCue? {
        guard let index = currentCueIndex, cues.indices.contains(index) else { return nil }
        return cues[index]
    }

    var hasSubtitles: Bool { !cues.isEmpty }

    // MARK: - 初期化

    init() {
        configureAudioSession()
        setupRemoteCommands()
        observePlayer()
        observeInterruptions()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// 再生カテゴリを .playback にすることで、消音スイッチが入っていても鳴り、
    /// かつバックグラウンドでも再生が続くようになる(Info.plist の UIBackgroundModes と対で必要)。
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("[PlayerEngine] オーディオセッションの設定に失敗: \(error)")
        }
    }

    // MARK: - 読み込み

    func load(audioURL: URL, subtitleURL: URL?, title: String, trackID: UUID, startAt: Double = 0) {
        let item = AVPlayerItem(url: audioURL)
        item.audioTimePitchAlgorithm = pitchAlgorithm
        player.replaceCurrentItem(with: item)

        self.title = title
        self.currentTrackID = trackID
        self.currentTime = startAt
        self.duration = 0
        self.isReady = false
        self.currentCueIndex = nil

        loadSubtitles(from: subtitleURL)
        observeItemStatus(item, startAt: startAt)
        updateNowPlayingInfo()
    }

    func loadSubtitles(from url: URL?) {
        guard let url else {
            cues = []
            groups = []
            currentCueIndex = nil
            currentGroupIndex = nil
            return
        }
        // 字幕ファイルの文字コードは UTF-8 とは限らないため、失敗したら Shift_JIS を試す
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS))
            ?? ""
        cues = SubtitleParser.parse(content)
        groups = cues.grouped()
        currentCueIndex = cues.cue(at: currentTime)
        currentGroupIndex = groups.group(at: currentTime)
        rebuildSkippedRanges()
    }

    private func observeItemStatus(_ item: AVPlayerItem, startAt: Double) {
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                let seconds = item.duration.seconds
                self.duration = seconds.isFinite ? seconds : 0
                self.isReady = true
                if startAt > 0, startAt < self.duration {
                    self.seek(to: startAt)
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - 再生操作

    func play() {
        guard isReady || player.currentItem != nil else { return }
        // rate 指定で再生を始めることで「1x で鳴ってから倍速に切り替わる」段差をなくす
        player.playImmediately(atRate: Float(speed))
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        persistPosition()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func skip(_ seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to time: Double) {
        let target = min(max(0, time), duration > 0 ? duration : time)
        // 字幕とずれないよう許容誤差ゼロでシークする
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
        // 強調位置もその場で更新する。次の定期更新を待つと、
        // 音が鳴り始めてから字幕が光るまでに間が空いて見える。
        currentCueIndex = cues.cue(at: target)
        let group = groups.group(at: target)
        currentGroupIndex = group
        if let group { highlightedGroupIndex = group }
        updateNowPlayingInfo()
    }

    /// スライダー操作中は時刻の自動更新を止める(つまみが指から逃げるのを防ぐ)。
    func beginScrubbing() {
        isScrubbing = true
    }

    func endScrubbing(at time: Double) {
        isScrubbing = false
        seek(to: time)
    }

    func previewScrub(to time: Double) {
        currentTime = time
        currentCueIndex = cues.cue(at: time)
        let group = groups.group(at: time)
        currentGroupIndex = group
        if let group { highlightedGroupIndex = group }
    }

    func jump(to cue: SubtitleCue) {
        seek(to: cue.start)
    }

    // MARK: - 速度と音程

    /// 倍速でも音程を保つ。時間領域方式は子音の輪郭が残り、話し声が聞き取りやすい。
    /// スペクトル方式は音楽向けで、話し声では反響がかかったようにぼやける。
    private let pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain

    private func applyRate() {
        guard isPlaying else { return }
        player.rate = Float(speed)
        updateNowPlayingInfo()
    }

    private func applyPitchAlgorithm() {
        guard let item = player.currentItem else { return }
        item.audioTimePitchAlgorithm = pitchAlgorithm

        // 方式を差し替えても、すでに読み込み済みの音声には適用されない。
        // 同じ位置へシークして音声パイプラインを作り直すことで即座に切り替える。
        let shouldResume = isPlaying
        let position = currentTime
        player.seek(
            to: CMTime(seconds: position, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self, shouldResume else { return }
            self.player.playImmediately(atRate: Float(self.speed))
        }
    }

    // MARK: - 監視

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            // 音声上の時間で刻むため、倍速時は実時間ではこれより短い間隔で発火する。
            // 0.1 秒にすると 3 倍速で毎秒 30 回になり、処理が追いつかず表示が遅れる。
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = seconds
            if self.skipLearnedIfNeeded(at: seconds) { return }
            self.updateCue(at: seconds)
            self.persistPosition()
        }

        rateObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.timeControlStatus == .playing
                self?.updateNowPlayingInfo()
            }
        }

        let endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
            self?.seek(to: 0)
        }
        notificationTokens.append(endToken)
    }

    /// 電話や他アプリの割り込みが終わったら再生を再開する。
    private func observeInterruptions() {
        let token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            switch type {
            case .began:
                self.pause()
            case .ended:
                if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                    self.play()
                }
            @unknown default:
                break
            }
        }
        notificationTokens.append(token)
    }

    private func updateCue(at time: Double) {
        // 直前のキューがまだ有効なら探索しない(0.1 秒ごとに呼ばれるため)
        if let index = currentCueIndex, cues.indices.contains(index) {
            let cue = cues[index]
            if time >= cue.start && time <= cue.end { return }
        }
        let found = cues.cue(at: time)
        let changed = found != currentCueIndex
        if changed { currentCueIndex = found }

        let g = groups.group(at: time)
        if g != currentGroupIndex { currentGroupIndex = g }

        // ロック画面は項目ごとの絵なので、項目が変わったときだけ描き替える。
        // 行ごとに更新すると回数が 4 倍になり、iOS 側で間引かれて古い絵が残る。
        if let g, g != highlightedGroupIndex {
            highlightedGroupIndex = g
            updateNowPlayingInfo()
        }
    }

    // MARK: - 覚えた項目を飛ばす

    /// 覚えた印の付いた項目に入ったら、次の未習項目まで送る。
    /// 送った場合は true を返し、この回の更新処理を打ち切る。
    @discardableResult
    private func skipLearnedIfNeeded(at time: Double) -> Bool {
        guard skipLearned, !learnedGroups.isEmpty, !groups.isEmpty else { return false }
        guard let index = groups.group(at: time), learnedGroups.contains(index) else { return false }

        if let next = groups.firstUnlearned(after: groups[index].end, learned: learnedGroups) {
            seek(to: next.start)
        } else {
            // この先すべて覚えている場合は最後まで送って停止する
            pause()
            seek(to: duration > 0 ? duration : time)
        }
        return true
    }

    func setLearned(_ learned: Bool, group: Int) {
        if learned {
            learnedGroups.insert(group)
        } else {
            learnedGroups.remove(group)
        }
        rebuildSkippedRanges()
    }

    func applyLearned(_ set: Set<Int>) {
        learnedGroups = set
        rebuildSkippedRanges()
    }

    // MARK: - 覚えた分を除いた時間

    /// 飛ばす区間。重なりをなくして開始順に並べてある。
    private var skippedRanges: [(start: Double, end: Double)] = []

    private func rebuildSkippedRanges() {
        guard skipLearned else {
            skippedRanges = []
            skippedDuration = 0
            return
        }
        let sorted = learnedGroups
            .compactMap { groups.indices.contains($0) ? groups[$0] : nil }
            .sorted { $0.start < $1.start }

        var merged: [(start: Double, end: Double)] = []
        for g in sorted {
            if let last = merged.last, g.start <= last.end {
                merged[merged.count-1].end = max(last.end, g.end)
            } else {
                merged.append((g.start, g.end))
            }
        }
        skippedRanges = merged
        skippedDuration = merged.reduce(0) { $0 + ($1.end - $1.start) }
    }

    /// 飛ばす区間の合計。表示の更新に使うので published にしておく。
    @Published private(set) var skippedDuration: Double = 0

    /// 覚えた分を差し引いた実質の長さ
    var effectiveDuration: Double {
        max(0, duration - skippedDuration)
    }

    /// 実時間を、飛ばす区間を詰めた時間に直す
    func effectiveTime(for real: Double) -> Double {
        var shift = 0.0
        for r in skippedRanges {
            if r.end <= real {
                shift += r.end - r.start
            } else if r.start < real {
                shift += real - r.start   // 区間の途中にいる場合
            } else {
                break
            }
        }
        return max(0, real - shift)
    }

    /// 詰めた時間を実時間に戻す(シークバー操作用)
    func realTime(for effective: Double) -> Double {
        var real = effective
        for r in skippedRanges {
            if r.start <= real {
                real += r.end - r.start
            } else {
                break
            }
        }
        return min(real, duration > 0 ? duration : real)
    }

    /// 操作の対象になる項目。項目と項目の隙間にいるときは、これから流れる項目を指す。
    /// 再生前(0 秒)は最初の項目のわずかに手前にいるため、これが無いとボタンが死ぬ。
    var activeGroupIndex: Int? {
        if let index = currentGroupIndex { return index }
        return groups.firstIndex { $0.start >= currentTime }
    }

    /// 今流れている項目の先頭へ戻す(聞き直し用)。
    func replayCurrentGroup() {
        guard let index = activeGroupIndex, groups.indices.contains(index) else { return }
        seek(to: groups[index].start)
    }

    func jumpToGroup(_ index: Int) {
        guard groups.indices.contains(index) else { return }
        seek(to: groups[index].start)
    }

    private func persistPosition() {
        guard let trackID = currentTrackID else { return }
        onPositionChange?(trackID, currentTime)
    }

    // MARK: - ロック画面 / コントロールセンター

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        updateRemoteSkipIntervals()
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.skip(self.skipInterval)
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.skip(-self.skipInterval)
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    /// ロック画面の送り・戻しに表示される秒数を設定に合わせる。
    private func updateRemoteSkipIntervals() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "倍速プレイヤー" : title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        // 文字欄にも今の項目の英文を出す。絵と同じ単位にしないと、
        // 絵は次の項目を指しているのに文字は前のまま、という食い違いが起きる。
        if let index = highlightedGroupIndex, groups.indices.contains(index),
           let headline = groups[index].lines(in: cues).first {
            info[MPMediaItemPropertyArtist] = headline.text.replacingOccurrences(of: "\n", with: " ")
        }
        if let artwork = lockScreenArtwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - ロック画面に出す字幕の絵

    private var artworkCacheKey: String?
    private var artworkCache: MPMediaItemArtwork?

    /// 前後の項目まで含めた絵を返す。内容が変わっていなければ描き直さない。
    /// 全画面プレイヤーで開いたときに、流れている箇所の前後を追えるようにするため。
    private func lockScreenArtwork() -> MPMediaItemArtwork? {
        guard let center = highlightedGroupIndex, groups.indices.contains(center) else {
            return artworkCache
        }

        // 前 1 件・後ろ 2 件。枠は正方形で高さがあるので、この数でも十分に大きく描ける。
        let lower = max(0, center - 1)
        let upper = min(groups.count - 1, center + 2)

        var items: [NowPlayingArtwork.Item] = []
        for index in lower...upper {
            var texts = groups[index].lines(in: cues).map(\.text)
            if !showsTranslation {
                let english = texts.filter { !$0.looksLikeTranslation }
                if !english.isEmpty { texts = english }
            }
            guard !texts.isEmpty else { continue }
            items.append(.init(lines: texts, isCurrent: index == center))
        }
        guard !items.isEmpty else { return artworkCache }

        let key = "\(lower)-\(center)-\(upper)-\(showsTranslation)"
        if key == artworkCacheKey, let cached = artworkCache { return cached }

        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 1024, height: 1024)) { size in
            NowPlayingArtwork.render(items: items, size: size)
        }
        artworkCacheKey = key
        artworkCache = artwork
        return artwork
    }
}
