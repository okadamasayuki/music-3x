import Foundation

struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
}

/// SRT / WebVTT の共通パーサー。
/// Web 版 (app.js) の `parseSubtitles` を Swift に移植したもので、
/// 両形式をブロック単位の同じ処理で扱う。
enum SubtitleParser {

    static func parse(_ content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        var cues: [SubtitleCue] = []

        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { continue }

            // タイムコード行を探す。WEBVTT ヘッダーや NOTE ブロックはここで弾かれる。
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }

            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count >= 2,
                  let start = parseTimestamp(parts[0]),
                  // VTT はタイムコードの後ろに位置指定が付くことがあるので先頭トークンのみ使う
                  let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)
                      .components(separatedBy: .whitespaces)[0])
            else { continue }

            var joined = lines[(timeIndex + 1)...].joined(separator: "\n")
            // 飾り札は VTT にしか出てこない。含む行だけ正規表現にかける。
            // 全件にかけると、その都度パターンを組み直すぶんだけ遅くなる。
            if joined.contains("<") {
                joined = joined.replacingOccurrences(
                    of: "<[^>]+>", with: "", options: .regularExpression)
            }
            let text = joined.trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: text))
            }
        }

        return cues.sorted { $0.start < $1.start }
    }

    /// "01:02:03,456" / "02:03.456" → 秒
    ///
    /// 正規表現は使わない。字幕 1 件につき 2 回呼ばれるため、数千件の教材では
    /// パターンを組み直す時間だけで数百ミリ秒かかり、開くまでの間が空いていた。
    private static func parseTimestamp(_ raw: String) -> Double? {
        let ts = raw.trimmingCharacters(in: .whitespaces)
        guard !ts.isEmpty else { return nil }

        // 末尾の「秒.ミリ秒」を切り出す
        guard let dot = ts.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
        let fraction = String(ts[ts.index(after: dot)...])
        guard (1...3).contains(fraction.count), fraction.allSatisfy(\.isNumber) else { return nil }

        // 残りを ":" で割る。時が無い形("02:03.456")も許す。
        let head = ts[..<dot].split(separator: ":", omittingEmptySubsequences: false)
        guard head.count == 2 || head.count == 3 else { return nil }

        var values: [Double] = []
        for part in head {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Double(part) else { return nil }
            values.append(value)
        }
        let hours = head.count == 3 ? values[0] : 0
        let minutes = values[head.count - 2]
        let seconds = values[head.count - 1]

        // "5" は 500ms、"05" は 50ms を意味するので右をゼロ埋めする
        let millis = Double(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        return hours * 3600 + minutes * 60 + seconds + millis / 1000
    }
}

extension Array where Element == SubtitleCue {
    /// 指定時刻を含むキューを二分探索で返す。timeupdate 相当の高頻度呼び出しを想定。
    func cue(at time: Double) -> Int? {
        var lo = 0
        var hi = count - 1
        var found: Int?

        while lo <= hi {
            let mid = (lo + hi) / 2
            if self[mid].start > time {
                hi = mid - 1
            } else {
                if time <= self[mid].end { found = mid }
                lo = mid + 1
            }
        }
        return found
    }
}
