import AVFoundation
import Combine

/// 音源の決まった区間だけを鳴らす、テスト用の小さな再生機。
///
/// 聞き取りテストでは、項目の英語の部分だけを鳴らして訳の手前で止めたい。
/// いつもの再生機(PlayerEngine)は覚えた分の飛ばし・ロック画面・位置の保存を
/// 抱えているので、それらに触れないよう別に持つ。
final class SegmentPlayer: ObservableObject {

    @Published private(set) var isPlaying = false

    /// 検証中に音を出さないための元栓。シミュレータを合図で動かしている間だけ閉める
    /// (RootView の TestSignals 受け口)。止め方は PlayerEngine.auditHardMuted と同じで、
    /// 音量ではなく isMuted を閉めるので、鳴り終わりの見張りなどの動きは変わらない。
    static var hardMuted = false
    var isHardMuted: Bool { player.isMuted }

    private let player = AVPlayer()
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    /// 何回目の再生か。追い越された古い再生の完了を見分けるために使う。
    private var generation = 0
    /// 区間を鳴らし終えたときに呼ぶ。止めたとき・差し替えたときは呼ばない。
    private var onFinish: (() -> Void)?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
    }

    deinit {
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func load(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        // 倍速でも話し声の子音が崩れにくい方式(PlayerEngine と同じ)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        // 映像付きの教材でも、映像は復号しない
        statusObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                for track in item.tracks where track.assetTrack?.mediaType == .video {
                    track.isEnabled = false
                }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        // 区間の終わりが音源の終わりと重なると境界の見張りが鳴らないことがあるので、こちらでも拾う
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            self?.finish(generation: self?.generation ?? -1)
        }
    }

    /// start から end までを rate の速さで鳴らす。鳴り終えたら finished を呼ぶ。
    func play(from start: Double, to end: Double, rate: Double, finished: @escaping () -> Void) {
        stop()
        generation += 1
        let my = generation
        onFinish = finished
        player.isMuted = Self.hardMuted
        try? AVAudioSession.sharedInstance().setActive(true)
        player.seek(
            to: CMTime(seconds: max(0, start), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] done in
            DispatchQueue.main.async {
                guard let self, done, my == self.generation else { return }
                let endTime = NSValue(time: CMTime(seconds: end, preferredTimescale: 600))
                self.boundaryObserver = self.player.addBoundaryTimeObserver(
                    forTimes: [endTime], queue: .main
                ) { [weak self] in
                    self?.finish(generation: my)
                }
                self.player.playImmediately(atRate: Float(rate))
                self.isPlaying = true
            }
        }
    }

    /// 鳴らすのをやめる。終わりの知らせは出さない。
    func stop() {
        generation += 1
        onFinish = nil
        player.pause()
        removeBoundary()
        isPlaying = false
    }

    private func finish(generation my: Int) {
        guard my == generation, isPlaying else { return }
        player.pause()
        removeBoundary()
        isPlaying = false
        let done = onFinish
        onFinish = nil
        done?()
    }

    private func removeBoundary() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
    }
}
