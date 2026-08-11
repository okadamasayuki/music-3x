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

    init(
        id: UUID = UUID(),
        audioFileName: String,
        subtitleFileName: String? = nil,
        displayName: String,
        addedAt: Date = Date(),
        lastPosition: Double = 0
    ) {
        self.id = id
        self.audioFileName = audioFileName
        self.subtitleFileName = subtitleFileName
        self.displayName = displayName
        self.addedAt = addedAt
        self.lastPosition = lastPosition
    }

    var hasSubtitle: Bool { subtitleFileName != nil }
}
