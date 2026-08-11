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

extension Array where Element == SubtitleCue {
    /// 一定以上の無音で区切って項目にまとめる。
    /// 字幕を作ったときと同じ考え方なので、生成物と食い違わない。
    func grouped(gap: Double = 0.8) -> [SubtitleGroup] {
        guard !isEmpty else { return [] }

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
