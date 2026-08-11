import Foundation

/// 字幕をまとまり(教材の 1 項目)に束ねたもの。
/// 語学教材は「英語 → 訳 → 英語 → 英語」のように数行で 1 項目を成すことが多く、
/// 覚えた分を飛ばすときも行単位ではなく項目単位で扱いたいため。
struct SubtitleGroup: Identifiable, Equatable {
    let id: Int
    /// この項目に含まれる字幕の添字(cues 配列に対する範囲)
    let range: Range<Int>
    let start: Double
    let end: Double

    var count: Int { range.count }
}

/// 一覧に出す 1 行。同じ文が項目内で複数回読まれる場合はまとめてある。
struct TranscriptLine: Identifiable {
    /// 先頭に現れたキューの添字をそのまま識別子にする
    let id: Int
    let text: String
    /// この行に対応するキュー(読み直しの分だけ複数になる)
    let cueIndices: [Int]

    var repeatCount: Int { cueIndices.count }
}

extension SubtitleGroup {
    /// 項目内の字幕を、同じ文はひとつにまとめて返す。
    /// 語学教材は同じ英文を 2〜3 回読むため、そのまま並べると画面が埋まってしまう。
    func lines(in cues: [SubtitleCue]) -> [TranscriptLine] {
        var order: [String] = []
        var indices: [String: [Int]] = [:]
        var display: [String: String] = [:]

        for i in range where cues.indices.contains(i) {
            let key = TranscriptLine.key(for: cues[i].text)
            if indices[key] == nil {
                order.append(key)
                display[key] = cues[i].text
            }
            indices[key, default: []].append(i)
        }

        return order.compactMap { key in
            guard let list = indices[key], let text = display[key], let first = list.first else { return nil }
            return TranscriptLine(id: first, text: text, cueIndices: list)
        }
    }
}

extension TranscriptLine {
    /// 大小や句読点の差を無視して同じ文とみなすための鍵。
    /// 認識のゆらぎで末尾の句点だけ違う、綴りが英米で揺れる、といった場合も同一視する。
    static func key(for text: String) -> String {
        let lowered = text.lowercased()
        let kept = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let words = String(String.UnicodeScalarView(kept))
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { spellingVariants[String($0)] ?? String($0) }
        return words.joined(separator: " ")
    }

    /// 英米で綴りが分かれる語。規則で機械的に変換すると hour → hor のような
    /// 誤りが出るため、実際に揺れる語だけを列挙する。
    private static let spellingVariants: [String: String] = [
        "behaviour": "behavior", "colour": "color", "favour": "favor",
        "favourite": "favorite", "labour": "labor", "neighbour": "neighbor",
        "honour": "honor", "humour": "humor", "rumour": "rumor",
        "travelling": "traveling", "travelled": "traveled", "traveller": "traveler",
        "centre": "center", "theatre": "theater", "metre": "meter", "fibre": "fiber",
        "realise": "realize", "organise": "organize", "recognise": "recognize",
        "apologise": "apologize", "criticise": "criticize", "emphasise": "emphasize",
        "analyse": "analyze", "paralyse": "paralyze",
        "defence": "defense", "offence": "offense", "licence": "license",
        "programme": "program", "grey": "gray", "cheque": "check",
        "jewellery": "jewelry", "practise": "practice",
    ]
}

extension Array where Element == SubtitleCue {
    /// 字幕を項目にまとめる。
    ///
    /// 語学教材のように「英文 → 訳 → 英文…」と訳が一定間隔で挟まる字幕では、
    /// 訳の行を目印にして区切る。無音の長さで区切ると、読み直しの前に間が空いた
    /// 項目が分断され、そこから先の区切りが丸ごとずれてしまうため。
    /// 訳が見当たらない普通の字幕では、従来どおり無音の長さで区切る。
    func grouped(gap: Double = 0.8) -> [SubtitleGroup] {
        guard !isEmpty else { return [] }
        return groupedByTranslation() ?? groupedBySilence(gap: gap)
    }

    /// 訳とみられる行を目印に区切る。目印が規則的に現れないときは nil を返す。
    private func groupedByTranslation() -> [SubtitleGroup]? {
        let marks = indices.filter { self[$0].text.looksLikeTranslation }
        // 訳が 2 文に分かれて読まれると続けて現れる。間に本文を挟まない訳は
        // ひとつの区切りとみなす。分けると 1 行だけの項目ができてしまう。
        var anchors: [Int] = []
        for (n, i) in marks.enumerated() where n == 0 || marks[n-1] != i - 1 {
            anchors.append(i)
        }
        // 全体の 1/6 以上が訳で、かつ先頭が訳でない(前に本文がある)ことを条件にする
        guard anchors.count >= 2, anchors.count * 6 >= count, let first = anchors.first, first > 0
        else { return nil }

        var groups: [SubtitleGroup] = []
        for (n, anchor) in anchors.enumerated() {
            let start = anchor - 1
            let end = n + 1 < anchors.count ? anchors[n+1] - 1 : count
            guard start >= 0, end > start else { continue }
            groups.append(SubtitleGroup(
                id: groups.count,
                range: start..<end,
                start: self[start].start,
                end: self[end-1].end
            ))
        }
        return groups.isEmpty ? nil : groups
    }

    private func groupedBySilence(gap: Double) -> [SubtitleGroup] {
        var groups: [SubtitleGroup] = []
        var startIndex = 0

        for i in 1..<count {
            if self[i].start - self[i-1].end >= gap {
                groups.append(SubtitleGroup(
                    id: groups.count,
                    range: startIndex..<i,
                    start: self[startIndex].start,
                    end: self[i-1].end
                ))
                startIndex = i
            }
        }
        groups.append(SubtitleGroup(
            id: groups.count,
            range: startIndex..<count,
            start: self[startIndex].start,
            end: self[count-1].end
        ))
        return groups
    }
}

extension String {
    /// かな・漢字が主体なら訳の行とみなす。
    var looksLikeTranslation: Bool {
        var japanese = 0
        var latin = 0
        for ch in unicodeScalars {
            if (0x3040...0x30FF).contains(ch.value) || (0x4E00...0x9FFF).contains(ch.value) {
                japanese += 1
            } else if (0x41...0x5A).contains(ch.value) || (0x61...0x7A).contains(ch.value) {
                latin += 1
            }
        }
        return japanese > 0 && japanese >= latin
    }
}

extension Array where Element == SubtitleGroup {
    /// 指定時刻を含む項目を二分探索で返す。
    func group(at time: Double) -> Int? {
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

    /// 指定時刻以降で、覚えていない最初の項目。
    func firstUnlearned(after time: Double, learned: Set<Int>) -> SubtitleGroup? {
        first { $0.start > time - 0.001 && !learned.contains($0.id) }
    }
}
