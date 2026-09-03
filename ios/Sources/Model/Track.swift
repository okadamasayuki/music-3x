import Foundation

/// 端末内に取り込んだ音源 1 件。
/// ファイル本体は Documents/Media に置き、ここではファイル名だけを保持する。
/// (アプリ再インストール時などに Documents の絶対パスが変わるため、絶対 URL は保存しない)
struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var audioFileName: String
    var subtitleFileName: String?
    var displayName: String
    var addedAt: Date
    /// 前回の再生位置(秒)。次回開いたときに続きから再生するために使う。
    var lastPosition: Double
    /// 覚えたので飛ばしてよい項目の番号。
    var learnedGroups: Set<Int>
    /// 覚えた印を付けたときの字幕の件数。字幕を差し替えると項目番号がずれるため、
    /// 件数が変わっていたら印を捨てる判断に使う。
    var learnedCueCount: Int
    /// 英作の練習で「できた」を付けた項目の番号。覚えた印とは別勘定。
    /// 聞いて分かることと、日本語から言えることは別の段階のため。
    var recallDoneGroups: Set<Int>
    /// できた印を付けたときの字幕の件数。learnedCueCount と同じ役目。
    var recallCueCount: Int

    init(
        id: UUID = UUID(),
        audioFileName: String,
        subtitleFileName: String? = nil,
        displayName: String,
        addedAt: Date = Date(),
        lastPosition: Double = 0,
        learnedGroups: Set<Int> = [],
        learnedCueCount: Int = 0,
        recallDoneGroups: Set<Int> = [],
        recallCueCount: Int = 0
    ) {
        self.id = id
        self.audioFileName = audioFileName
        self.subtitleFileName = subtitleFileName
        self.displayName = displayName
        self.addedAt = addedAt
        self.lastPosition = lastPosition
        self.learnedGroups = learnedGroups
        self.learnedCueCount = learnedCueCount
        self.recallDoneGroups = recallDoneGroups
        self.recallCueCount = recallCueCount
    }

    // 既存の保存データには覚えた印が無いので、無い場合は空として読む
    enum CodingKeys: String, CodingKey {
        case id, audioFileName, subtitleFileName, displayName, addedAt, lastPosition
        case learnedGroups, learnedCueCount
        case recallDoneGroups, recallCueCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        audioFileName = try c.decode(String.self, forKey: .audioFileName)
        subtitleFileName = try c.decodeIfPresent(String.self, forKey: .subtitleFileName)
        displayName = try c.decode(String.self, forKey: .displayName)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        lastPosition = try c.decode(Double.self, forKey: .lastPosition)
        learnedGroups = try c.decodeIfPresent(Set<Int>.self, forKey: .learnedGroups) ?? []
        learnedCueCount = try c.decodeIfPresent(Int.self, forKey: .learnedCueCount) ?? 0
        recallDoneGroups = try c.decodeIfPresent(Set<Int>.self, forKey: .recallDoneGroups) ?? []
        recallCueCount = try c.decodeIfPresent(Int.self, forKey: .recallCueCount) ?? 0
    }

    var hasSubtitle: Bool { subtitleFileName != nil }
}
