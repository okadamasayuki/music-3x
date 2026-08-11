import AVFoundation

/// 倍速時に音程を保つ方式。方式によって声の聞こえ方がはっきり変わるため、
/// 好みに合わせて選べるようにしている。
enum StretchMode: String, CaseIterable, Identifiable {
    /// 時間領域方式。子音の輪郭が残り、話し声が聞き取りやすい。
    /// YouTube などの倍速再生に近い聞こえ方。
    case speech
    /// スペクトル方式。音楽や環境音の質感を保つが、
    /// 話し声では反響がかかったようにぼやけることがある。
    case music

    var id: String { rawValue }

    var algorithm: AVAudioTimePitchAlgorithm {
        switch self {
        case .speech: return .timeDomain
        case .music: return .spectral
        }
    }

    var label: String {
        switch self {
        case .speech: return "話し声"
        case .music: return "音楽"
        }
    }

    // MARK: - 保存

    private static let storageKey = "stretchMode"

    static var saved: StretchMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let mode = StretchMode(rawValue: raw)
        else { return .speech }
        return mode
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}
