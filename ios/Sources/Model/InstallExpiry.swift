import Foundation

/// このアプリがいつまで起動できるかを、署名情報から読み取る。
///
/// 無料の Apple ID で入れたアプリは 7 日で起動できなくなる。
/// 期限はアプリに埋め込まれた証明情報に入っているので、そこから取る。
enum InstallExpiry {

    static let expirationDate: Date? = readExpirationDate()

    /// 残り日数。期限切れなら 0 を返す。
    static var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        let seconds = expirationDate.timeIntervalSinceNow
        return seconds <= 0 ? 0 : Int(ceil(seconds / 86_400))
    }

    static var formattedDate: String? {
        guard let expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E) HH:mm"
        return formatter.string(from: expirationDate)
    }

    private static func readExpirationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }

        // 署名で包まれているので、中の設定情報の部分だけを取り出す
        guard let start = range(of: "<?xml", in: data),
              let end = range(of: "</plist>", in: data), end.upperBound > start.lowerBound
        else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let parsed = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        return (parsed as? [String: Any])?["ExpirationDate"] as? Date
    }

    private static func range(of text: String, in data: Data) -> Range<Data.Index>? {
        guard let pattern = text.data(using: .utf8) else { return nil }
        return data.range(of: pattern)
    }
}
