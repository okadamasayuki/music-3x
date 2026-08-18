import Foundation

/// アプリ自体への改善要望のひとつ。
struct Improvement: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// Mac へ送って実装が始まった日時。まだ送っていなければ nil。
    var sentAt: Date?
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

    /// まだ送っていない項目。新しいものが上。
    var pending: [Improvement] { items.filter { $0.sentAt == nil } }
    /// 送信済みの項目。実装されたかを後で見返すために残す。
    var sent: [Improvement] { items.filter { $0.sentAt != nil } }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(Improvement(text: trimmed), at: 0)
        save()
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func markSent(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].sentAt = Date()
        save()
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Improvement].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
