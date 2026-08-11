import UIKit

/// ロック画面のアートワーク枠に字幕を描く。
///
/// iOS はロック画面に任意の内容を全画面表示させてくれないが、
/// 再生中の曲の絵として画像を渡すことはできる。そこへ字幕を描けば、
/// ロック画面で最も大きい領域を字幕に使える。
enum NowPlayingArtwork {

    /// 項目の各行を、今流れている行だけ強調して 1 枚の画像にする。
    /// - Parameters:
    ///   - lines: 上から順に並べる行
    ///   - highlighted: 強調する行の位置。範囲外なら強調なし。
    static func render(lines: [String], highlighted: Int, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
            context.fill(rect)

            guard !lines.isEmpty else { return }

            let margin = size.width * 0.07
            let available = rect.insetBy(dx: margin, dy: margin)

            // 行数と文字量から、収まる最大の文字サイズを二分探索で決める。
            // 語学教材は 1 行が短いので、収まる限り大きくした方が読みやすい。
            var low = size.width * 0.030
            var high = size.width * 0.115
            var best = low
            for _ in 0..<12 {
                let mid = (low + high) / 2
                if totalHeight(lines: lines, fontSize: mid, width: available.width) <= available.height {
                    best = mid
                    low = mid
                } else {
                    high = mid
                }
            }

            var y = available.minY + (available.height - totalHeight(lines: lines, fontSize: best, width: available.width)) / 2
            for (i, line) in lines.enumerated() {
                let isCurrent = i == highlighted
                let attrs = attributes(fontSize: best, current: isCurrent)
                let bounds = boundingRect(line, attributes: attrs, width: available.width)
                let box = CGRect(x: available.minX, y: y, width: available.width, height: bounds.height)

                if isCurrent {
                    let pad = best * 0.28
                    let bg = box.insetBy(dx: -pad * 0.6, dy: -pad * 0.35)
                    UIColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 0.30).setFill()
                    UIBezierPath(roundedRect: bg, cornerRadius: pad).fill()
                }
                (line as NSString).draw(with: box, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                y += bounds.height + best * 0.75
            }
        }
    }

    private static func attributes(fontSize: CGFloat, current: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: UIFont.systemFont(ofSize: fontSize, weight: current ? .semibold : .regular),
            .foregroundColor: current ? UIColor.white : UIColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph,
        ]
    }

    private static func boundingRect(_ text: String,
                                     attributes: [NSAttributedString.Key: Any],
                                     width: CGFloat) -> CGRect {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
    }

    private static func totalHeight(lines: [String], fontSize: CGFloat, width: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for (i, line) in lines.enumerated() {
            total += boundingRect(line, attributes: attributes(fontSize: fontSize, current: false), width: width).height
            if i < lines.count - 1 { total += fontSize * 0.75 }
        }
        return total
    }
}
