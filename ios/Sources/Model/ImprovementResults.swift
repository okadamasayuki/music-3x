import Foundation

/// Claude Code からの対応結果(要望ごとの「何をどう直したか」のまとめ)。
/// Mac 側が devicectl で Documents/improve_results.json へ書き込み、
/// 改善タブの「対応済み」欄に出る。
struct ImprovementResult: Identifiable, Codable, Equatable {
    var id = UUID()
    /// 要望の要約(1 行)
    var title: String
    /// 原因と対応内容のまとめ
    var summary: String
    var completedAt = Date()
}

/// 対応結果の読み書き。ファイルが正で、削除もファイルへ映す。
final class ImprovementResultStore: ObservableObject {

    @Published private(set) var results: [ImprovementResult] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improve_results.json")
    }

    init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ImprovementResult].self, from: data) else {
            results = []
            return
        }
        // 読んだら終わりの知らせなので、一日たったものは自動で消す
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let fresh = decoded.filter { $0.completedAt > cutoff }
        results = fresh.sorted { $0.completedAt > $1.completedAt }
        if fresh.count != decoded.count { persist() }
    }

    func remove(_ id: UUID) {
        results.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        results = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
