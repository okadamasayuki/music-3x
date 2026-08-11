import AVFoundation
import Combine
import MediaPlayer

/// AVPlayer をラップした再生エンジン。
/// 倍速・字幕同期・ロック画面操作・バックグラウンド再生をここで面倒を見る。
final class PlayerEngine: ObservableObject {

    /// ワンタップで選べる速度。Web 版の 1x/2x/3x/4x に半段刻みを足したもの。
    static let presetSpeeds: [Double] = [1, 1.5, 2, 2.5, 3, 4]
    static let speedRange: ClosedRange<Double> = 0.5...4.0
    static let skipInterval: Double = 10

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isReady = false
    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var title: String = ""

    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var currentCueIndex: Int?

    @Published var speed: Double = 1.0 {
        didSet { applyRate() }
    }

    @Published var preservesPitch: Bool = true {
        didSet { applyPitchAlgorithm() }
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
            currentCueIndex = nil
            return
        }
        // 字幕ファイルの文字コードは UTF-8 とは限らないため、失敗したら Shift_JIS を試す
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .shiftJIS))
            ?? ""
        cues = SubtitleParser.parse(content)
        currentCueIndex = cues.cue(at: currentTime)
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
        currentCueIndex = cues.cue(at: target)
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
    }

    func jump(to cue: SubtitleCue) {
        seek(to: cue.start)
    }

    // MARK: - 速度と音程

    private var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        // .spectral は音程を保ったまま速度を変える。高倍速でも声が甲高くならない。
        // オフのときの .varispeed はテープ早回しと同じで音程が上がる。
        preservesPitch ? .spectral : .varispeed
    }

    private func applyRate() {
        guard isPlaying else { return }
        player.rate = Float(speed)
        updateNowPlayingInfo()
    }

    private func applyPitchAlgorithm() {
        player.currentItem?.audioTimePitchAlgorithm = pitchAlgorithm
        // アルゴリズム変更を今の再生に反映させるため rate を入れ直す
        if isPlaying { player.rate = Float(speed) }
    }

    // MARK: - 監視

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = seconds
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
        if found != currentCueIndex { currentCueIndex = found }
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

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(Self.skipInterval)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(-Self.skipInterval)
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
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
        if let cue = currentCue {
            // ロック画面のアーティスト欄に字幕を出す。画面を見ずに聞くときの手がかりになる。
            info[MPMediaItemPropertyArtist] = cue.text.replacingOccurrences(of: "\n", with: " ")
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
