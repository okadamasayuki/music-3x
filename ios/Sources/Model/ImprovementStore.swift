import Foundation

/// アプリ自体への改善要望のひとつ。
struct Improvement: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// 昔の保存にだけ残っている「送った日時」。いまは送れた項目を
    /// その場で消すので、新しく付くことはない。読み込みのために残す。
    var sentAt: Date?
    /// 添付(写真・動画)のファイル名。実体は Documents/improve_media/ に置く。
    var attachments: [String]? = nil
}

/// 改善要望を端末に保管する。
///
/// 出先で思いついたことを放り込んでおき、家に帰って Mac が点いているときに
/// 送るまでの置き場。音源のライブラリとは役目が違うので、別のファイルに持つ。
final class ImprovementStore: ObservableObject {

    @Published private(set) var items: [Improvement] = []

    /// Documents 直下に置く。「ファイル」アプリからも見えるので、
    /// 送る仕組みが壊れたときでも中身を取り出せる。
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improvements.json")
    }

    init() {
        load()
    }

    /// 添付ファイル(写真・動画)の置き場。
    static var mediaDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improve_media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func add(_ text: String, attachments: [String]? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments ?? []
        guard !trimmed.isEmpty || !files.isEmpty else { return }
        // 画面の見せたい場所だけ撮って送る、という使い方があるので文は無くてもよい
        items.insert(Improvement(text: trimmed.isEmpty ? "(添付のみ)" : trimmed,
                                 attachments: files.isEmpty ? nil : files), at: 0)
        save()
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
        save()
    }

    func remove(_ id: UUID) {
        // 添付の実体も一緒に片付ける。項目を消したのに写真だけ残ると
        // 端末の容量を黙って食い続ける。
        if let item = items.first(where: { $0.id == id }) {
            for name in item.attachments ?? [] {
                try? FileManager.default.removeItem(at: Self.mediaDir.appendingPathComponent(name))
            }
        }
        items.removeAll { $0.id == id }
        save()
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Improvement].self, from: data) else { return }
        // 送信済みのまま残っていた項目は、ここで片付ける。実装の済んだものを
        // 一覧に置いておかない、という求めによる。控えは Mac 側の受信箱にある。
        items = decoded.filter { $0.sentAt == nil }
        if items.count != decoded.count { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
