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
    /// お気に入りに入れた項目の番号。まとめて繰り返し聞くために使う。
    var favoriteGroups: Set<Int>
    /// お気に入りを付けたときの字幕の件数。覚えた印と同じ理由で持つ。
    var favoriteCueCount: Int

    init(
        id: UUID = UUID(),
        audioFileName: String,
        subtitleFileName: String? = nil,
        displayName: String,
        addedAt: Date = Date(),
        lastPosition: Double = 0,
        learnedGroups: Set<Int> = [],
        learnedCueCount: Int = 0,
        favoriteGroups: Set<Int> = [],
        favoriteCueCount: Int = 0
    ) {
        self.id = id
        self.audioFileName = audioFileName
        self.subtitleFileName = subtitleFileName
        self.displayName = displayName
        self.addedAt = addedAt
        self.lastPosition = lastPosition
        self.learnedGroups = learnedGroups
        self.learnedCueCount = learnedCueCount
        self.favoriteGroups = favoriteGroups
        self.favoriteCueCount = favoriteCueCount
    }

    // 既存の保存データには覚えた印が無いので、無い場合は空として読む
    enum CodingKeys: String, CodingKey {
        case id, audioFileName, subtitleFileName, displayName, addedAt, lastPosition
        case learnedGroups, learnedCueCount
        case favoriteGroups, favoriteCueCount
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
        favoriteGroups = try c.decodeIfPresent(Set<Int>.self, forKey: .favoriteGroups) ?? []
        favoriteCueCount = try c.decodeIfPresent(Int.self, forKey: .favoriteCueCount) ?? 0
    }

    var hasSubtitle: Bool { subtitleFileName != nil }
}
