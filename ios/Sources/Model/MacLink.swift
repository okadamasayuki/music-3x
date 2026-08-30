import Foundation

/// 家の Mac に置いた受け口(mac/improvement_server.py)との橋渡し。
///
/// 同じ Wi-Fi の中だけで使う前提で、暗号化はしていない。
/// 送るのは自分で書いた改善メモだけで、外のネットワークへは何も出さない。
enum MacLink {

    /// 設定に書かれた「ホスト名:ポート」から URL を組む。
    static func url(host: String, path: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "http://\(trimmed)\(path)")
    }

    /// 受け口が生きているかを軽く叩いて確かめる。画面の隅の表示に使う。
    static func ping(host: String) async -> Bool {
        guard let url = url(host: host, path: "/ping") else { return false }
        let request = URLRequest(url: url, timeoutInterval: 3)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    enum SendError: LocalizedError {
        case badHost
        case unreachable
        case rejected(Int)

        var errorDescription: String? {
            switch self {
            case .badHost:
                return "送り先が設定されていません。設定タブで Mac のホスト名を確かめてください。"
            case .unreachable:
                return "Mac に届きませんでした。家の Wi-Fi にいて、Mac が起きているか確かめてください。"
            case .rejected(let code):
                return "Mac 側の受け口が受け付けませんでした。(HTTP \(code))"
            }
        }
    }

    /// 改善要望を Mac へ送る。届くと受信箱に入り、常駐セッションが実装を始める。
    /// 添付(写真・動画)があれば base64 で一緒に送る。同じ Wi-Fi の中だけ
    /// なので、多少かさばっても許す。そのぶん待ち時間は長めに取る。
    static func send(_ improvement: Improvement, host: String) async throws {
        guard let url = url(host: host, path: "/implement") else { throw SendError.badHost }
        let hasMedia = !(improvement.attachments ?? []).isEmpty
        var request = URLRequest(url: url, timeoutInterval: hasMedia ? 120 : 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "id": improvement.id.uuidString,
            "text": improvement.text,
            "createdAt": ISO8601DateFormatter().string(from: improvement.createdAt),
        ]
        if hasMedia {
            var files: [[String: String]] = []
            for name in improvement.attachments ?? [] {
                let fileURL = ImprovementStore.mediaDir.appendingPathComponent(name)
                if let data = try? Data(contentsOf: fileURL) {
                    files.append(["name": name, "data": data.base64EncodedString()])
                }
            }
            body["attachments"] = files
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let code: Int
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            code = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw SendError.unreachable
        }
        guard code == 200 else { throw SendError.rejected(code) }
    }
}
