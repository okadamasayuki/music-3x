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

            let text = lines[(timeIndex + 1)...]
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: text))
            }
        }

        return cues.sorted { $0.start < $1.start }
    }

    /// "01:02:03,456" / "02:03.456" → 秒
    private static func parseTimestamp(_ raw: String) -> Double? {
        let ts = raw.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(?:(\d+):)?(\d+):(\d+)[.,](\d{1,3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: ts, range: NSRange(ts.startIndex..., in: ts))
        else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(m.range(at: index), in: ts) else { return nil }
            return String(ts[range])
        }

        let hours = Double(group(1) ?? "0") ?? 0
        guard let minutes = Double(group(2) ?? ""),
              let seconds = Double(group(3) ?? ""),
              let fraction = group(4)
        else { return nil }

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
