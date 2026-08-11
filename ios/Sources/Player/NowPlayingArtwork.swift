import UIKit

/// ロック画面と全画面プレイヤーに出す絵を描く。
///
/// iOS はロック画面に任意の内容を全画面表示させてくれないが、
/// 再生中の曲の絵は渡せる。ここへ字幕を描いておくと、
/// サムネイルを開いたときに前後の項目まで大きく読める。
enum NowPlayingArtwork {

    /// 描く 1 項目。数行の字幕と、今流れているかどうか。
    struct Item {
        let lines: [String]
        let isCurrent: Bool
    }

    /// 項目を上から順に並べた絵を返す。今の項目だけを白く強調し、前後は控えめにする。
    static func render(items: [Item], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
            context.fill(rect)

            let flat = items.filter { !$0.lines.isEmpty }
            guard !flat.isEmpty else { return }

            let margin = size.width * 0.06
            let available = rect.insetBy(dx: margin, dy: margin)

            // 収まる最大の文字サイズを二分探索で決める。項目数が少ないほど大きくなる。
            var low = size.width * 0.022
            var high = size.width * 0.105
            var best = low
            for _ in 0..<14 {
                let mid = (low + high) / 2
                if layoutHeight(flat, fontSize: mid, width: available.width) <= available.height {
                    best = mid
                    low = mid
                } else {
                    high = mid
                }
            }

            let total = layoutHeight(flat, fontSize: best, width: available.width)
            var y = available.minY + max(0, (available.height - total) / 2)

            for item in flat {
                let blockHeight = itemHeight(item, fontSize: best, width: available.width)

                if item.isCurrent {
                    let pad = best * 0.34
                    let box = CGRect(x: available.minX - pad * 0.5, y: y - pad * 0.45,
                                     width: available.width + pad, height: blockHeight + pad * 0.9)
                    UIColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 0.28).setFill()
                    UIBezierPath(roundedRect: box, cornerRadius: pad).fill()
                }

                for (i, line) in item.lines.enumerated() {
                    let attrs = attributes(fontSize: best, current: item.isCurrent, secondary: i > 0)
                    let h = boundingRect(line, attributes: attrs, width: available.width).height
                    (line as NSString).draw(
                        with: CGRect(x: available.minX, y: y, width: available.width, height: h),
                        options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                    y += h
                }
                y += best * 0.85     // 項目と項目の間
            }
        }
    }

    private static func attributes(fontSize: CGFloat,
                                   current: Bool,
                                   secondary: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let alpha: CGFloat
        switch (current, secondary) {
        case (true, false): alpha = 1.0
        case (true, true): alpha = 0.78
        case (false, false): alpha = 0.42
        case (false, true): alpha = 0.30
        }
        return [
            .font: UIFont.systemFont(ofSize: secondary ? fontSize * 0.86 : fontSize,
                                     weight: current && !secondary ? .semibold : .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ]
    }

    private static func boundingRect(_ text: String,
                                     attributes: [NSAttributedString.Key: Any],
                                     width: CGFloat) -> CGRect {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
    }

    private static func itemHeight(_ item: Item, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        item.lines.enumerated().reduce(0) { total, pair in
            total + boundingRect(pair.element,
                                 attributes: attributes(fontSize: fontSize,
                                                        current: item.isCurrent,
                                                        secondary: pair.offset > 0),
                                 width: width).height
        }
    }

    private static func layoutHeight(_ items: [Item], fontSize: CGFloat, width: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for (i, item) in items.enumerated() {
            total += itemHeight(item, fontSize: fontSize, width: width)
            if i < items.count - 1 { total += fontSize * 0.85 }
        }
        return total
    }
}
