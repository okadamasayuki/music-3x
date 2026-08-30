import Foundation

/// 「覚えた項目が一瞬でも鳴らないか」を、音を出さずに確かめる検証装置。
///
/// シミュレータで環境変数と一緒に起動すると、名前に audit を含む音源を
/// 消音のまま再生し、20ms 刻みで「どの位置を・どの音量で」再生していたかを
/// 記録して Documents/audit_result.json に書き出す。覚えた項目の中で音量が
/// 生きていた瞬間があれば、それが漏れ。判定は Mac 側の解析にゆだねる。
///
/// ふだんの起動では環境変数が無いので、何もしない。
enum SkipAudit {

    static func startIfRequested(player: PlayerEngine, library: LibraryStore) {
        let env = ProcessInfo.processInfo.environment
        guard let speedText = env["AUDIT_SPEED"], let speed = Double(speedText) else { return }
        let learned = Set((env["AUDIT_LEARNED"] ?? "").split(separator: ",").compactMap { Int($0) })
        let seconds = Double(env["AUDIT_SECONDS"] ?? "30") ?? 30
        let startAt = Double(env["AUDIT_START"] ?? "0") ?? 0
        // 「実秒@行き先」の並び。例 "3@78.5,6@120" は開始 3 秒後に 78.5 秒へ飛ぶ
        var pendingSeeks: [(at: Double, to: Double)] = (env["AUDIT_SEEKS"] ?? "")
            .split(separator: ",").compactMap {
                let parts = $0.split(separator: "@")
                guard parts.count == 2, let at = Double(parts[0]), let to = Double(parts[1]) else { return nil }
                return (at, to)
            }
        // 「実秒」の並び。その時刻に再生を止め、0.3 秒後に押し直す
        var pendingPauses: [Double] = (env["AUDIT_PAUSES"] ?? "")
            .split(separator: ",").compactMap { Double($0) }

        guard let track = library.tracks.first(where: { $0.displayName.localizedCaseInsensitiveContains("audit") }) else {
            write(["error": "audit track not found"])
            return
        }

        player.auditHardMuted = true
        player.skipLearned = true
        player.load(audioURL: library.audioURL(for: track),
                    subtitleURL: library.subtitleURL(for: track),
                    title: track.displayName, trackID: track.id, startAt: startAt)
        player.speed = speed

        var samples: [[Double]] = []   // [実経過秒, 音声位置, 音量, 再生中か]
        var timer: Timer?
        var begun = Date()

        func finish() {
            timer?.invalidate()
            player.pause()
            write([
                "speed": speed,
                "learned": Array(learned).sorted(),
                "groups": player.groups.map { [$0.start, $0.end] },
                "samples": samples,
            ])
        }

        func waitReady() {
            guard player.isReady else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitReady() }
                return
            }
            player.applyLearned(learned)
            begun = Date()
            player.play()
            timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
                let elapsed = Date().timeIntervalSince(begun)
                samples.append([elapsed, player.auditPreciseTime,
                                Double(player.auditVolume), player.isPlaying ? 1 : 0])
                if let next = pendingSeeks.first, elapsed >= next.at {
                    pendingSeeks.removeFirst()
                    player.seek(to: next.to)
                }
                if let at = pendingPauses.first, elapsed >= at {
                    pendingPauses.removeFirst()
                    player.pause()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { player.play() }
                }
                if elapsed >= seconds { finish() }
            }
        }
        waitReady()
    }

    private static func write(_ payload: [String: Any]) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audit_result.json")
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
