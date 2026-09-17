import Foundation

/// 単語カード 1 枚。英単語・第一義の訳・それぞれの音声ファイル名を持つ。
/// 音声は単語ごとに分けて保存してあり、再生順はアプリ側で自由に組める。
struct WordCard: Identifiable, Codable, Equatable {
    let num: Int
    let en: String
    let ja: String
    let enAudio: String
    let jaAudio: String
    var id: Int { num }
}

/// 単語帳(デッキ)。Documents/WordDecks/<フォルダ>/ に
/// words.json と audio/ を置く。words.json をそのまま読み込む。
struct WordDeck: Identifiable, Equatable {
    let id: String          // フォルダ名
    let name: String
    let level: String
    let words: [WordCard]
    let directory: URL

    func audioURL(_ fileName: String) -> URL {
        directory.appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func == (a: WordDeck, b: WordDeck) -> Bool { a.id == b.id && a.words.count == b.words.count }
}

/// 端末内の単語帳を探して一覧にする。
final class WordDeckStore: ObservableObject {

    @Published private(set) var decks: [WordDeck] = []

    /// 単語帳の置き場。「ファイル」アプリからも見えるよう Documents 直下に作る。
    private(set) lazy var root: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("WordDecks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() { load() }

    func refresh() { load() }

    func deck(id: String) -> WordDeck? { decks.first { $0.id == id } }

    private struct Manifest: Decodable {
        let name: String
        let level: String?
        let words: [WordCard]
    }

    private func load() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var out: [WordDeck] = []
        for dir in dirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let manifestURL = dir.appendingPathComponent("words.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let m = try? JSONDecoder().decode(Manifest.self, from: data),
                  !m.words.isEmpty else { continue }
            out.append(WordDeck(id: dir.lastPathComponent, name: m.name,
                                level: m.level ?? "", words: m.words, directory: dir))
        }
        decks = out.sorted { $0.name < $1.name }
    }
}
