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

    /// 前面に戻ったときなど、アプリの外でファイルが増えている可能性がある場面で呼ぶ。
    func refresh() {
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

    // MARK: - 覚えた項目

    func setLearned(_ learned: Bool, group: Int, cueCount: Int, for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        // 字幕を差し替えて項目の区切りが変わっていたら、古い印は当てにならないので捨てる
        if tracks[index].learnedCueCount != cueCount {
            tracks[index].learnedGroups = []
            tracks[index].learnedCueCount = cueCount
        }
        if learned {
            tracks[index].learnedGroups.insert(group)
        } else {
            tracks[index].learnedGroups.remove(group)
        }
        save()
    }

    func clearLearned(for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].learnedGroups = []
        save()
    }

    /// 保存されている印が今の字幕に対応しているときだけ返す。
    func learnedGroups(for trackID: UUID, cueCount: Int) -> Set<Int> {
        guard let track = tracks.first(where: { $0.id == trackID }),
              track.learnedCueCount == cueCount else { return [] }
        return track.learnedGroups
    }

    // MARK: - お気に入り

    func setFavorite(_ favorite: Bool, group: Int, cueCount: Int, for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if tracks[index].favoriteCueCount != cueCount {
            tracks[index].favoriteGroups = []
            tracks[index].favoriteCueCount = cueCount
        }
        if favorite {
            tracks[index].favoriteGroups.insert(group)
        } else {
            tracks[index].favoriteGroups.remove(group)
        }
        save()
    }

    func clearFavorites(for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].favoriteGroups = []
        save()
    }

    func favoriteGroups(for trackID: UUID, cueCount: Int) -> Set<Int> {
        guard let track = tracks.first(where: { $0.id == trackID }),
              track.favoriteCueCount == cueCount else { return [] }
        return track.favoriteGroups
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
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            // 実体が消えているエントリ(ファイルアプリで直接削除された等)は落とす
            tracks = decoded.filter {
                FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent($0.audioFileName).path)
            }
        }
        discoverUnindexedFiles()
        linkMatchingSubtitles()
    }

    /// 音源と同じ名前の字幕が後から置かれた場合に紐付ける。
    /// 取り込み時にしか探していないと、字幕だけ後から入れたときに気づけない。
    private func linkMatchingSubtitles() {
        var changed = false
        for (index, track) in tracks.enumerated() where track.subtitleFileName == nil {
            let base = (track.audioFileName as NSString).deletingPathExtension
            if let found = existingSubtitleFileName(matching: base) {
                tracks[index].subtitleFileName = found
                changed = true
            }
        }
        if changed { save() }
    }

    /// Finder や「ファイル」アプリから Media へ直接置かれた音源を拾って一覧に加える。
    /// アプリの取り込み画面を通さずにファイルを入れても使えるようにするため。
    private func discoverUnindexedFiles() {
        let known = Set(tracks.map(\.audioFileName))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path) else { return }

        let discovered = names
            .filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { !known.contains($0) }
            .sorted()

        guard !discovered.isEmpty else { return }

        for name in discovered {
            let base = (name as NSString).deletingPathExtension
            tracks.insert(
                Track(
                    audioFileName: name,
                    subtitleFileName: existingSubtitleFileName(matching: base),
                    displayName: base
                ),
                at: 0
            )
        }
        save()
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "mov",
    ]

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
