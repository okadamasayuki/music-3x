import Foundation

/// 取り込み済みの音源・字幕をアプリ内に保管して一覧を管理する。
final class LibraryStore: ObservableObject {

    @Published private(set) var tracks: [Track] = []

    private let indexFileName = "library.json"

    /// 音源と字幕の実体を置くフォルダ。
    /// 「ファイル」アプリからも見えるよう Documents 直下に作る。
    private(set) lazy var mediaDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let media = documents.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }()

    private var indexURL: URL {
        mediaDirectory.appendingPathComponent(indexFileName)
    }

    init() {
        load()
    }

    // MARK: - 参照

    func audioURL(for track: Track) -> URL {
        mediaDirectory.appendingPathComponent(track.audioFileName)
    }

    func subtitleURL(for track: Track) -> URL? {
        track.subtitleFileName.map { mediaDirectory.appendingPathComponent($0) }
    }

    // MARK: - 取り込み

    /// ファイルアプリ等から選ばれた音源を端末内にコピーして一覧へ追加する。
    /// 同名ファイルがすでにある場合は連番を付けて別物として扱う。
    @discardableResult
    func importAudio(from source: URL) throws -> Track {
        let fileName = try copyIntoLibrary(source)
        let base = (fileName as NSString).deletingPathExtension

        // 同じ名前の字幕をすでに持っていれば自動で紐付ける
        let matchingSubtitle = existingSubtitleFileName(matching: base)

        let track = Track(
            audioFileName: fileName,
            subtitleFileName: matchingSubtitle,
            displayName: (source.lastPathComponent as NSString).deletingPathExtension
        )
        tracks.insert(track, at: 0)
        save()
        return track
    }

    /// 字幕を取り込んで指定トラックに紐付ける。
    func importSubtitle(from source: URL, for trackID: UUID) throws {
        let fileName = try copyIntoLibrary(source)
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].subtitleFileName = fileName
        save()
    }

    func remove(_ track: Track) {
        try? FileManager.default.removeItem(at: audioURL(for: track))
        if let subtitle = subtitleURL(for: track) {
            try? FileManager.default.removeItem(at: subtitle)
        }
        tracks.removeAll { $0.id == track.id }
        save()
    }

    func rename(_ track: Track, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[index].displayName = trimmed
        save()
    }

    func updatePosition(_ position: Double, for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        // 1 秒未満の差では書き込まない(再生中に毎秒保存すると無駄が大きい)
        guard abs(tracks[index].lastPosition - position) >= 1 else { return }
        tracks[index].lastPosition = position
        save()
    }

    // MARK: - 内部処理

    /// セキュリティスコープ付き URL から Documents/Media へ実体をコピーし、保存先のファイル名を返す。
    private func copyIntoLibrary(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let destination = uniqueDestination(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination.lastPathComponent
    }

    private func uniqueDestination(for fileName: String) -> URL {
        let candidate = mediaDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            let url = mediaDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }

    private func existingSubtitleFileName(matching base: String) -> String? {
        let candidates = ["\(base).srt", "\(base).vtt"]
        return candidates.first { name in
            FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent(name).path)
        }
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Track].self, from: data)
        else { return }

        // 実体が消えているエントリ(ファイルアプリで直接削除された等)は落とす
        tracks = decoded.filter {
            FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent($0.audioFileName).path)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
