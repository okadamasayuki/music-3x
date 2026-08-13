import Foundation

/// 英単語を「音の骨格」に直す。
///
/// 聞き違いは綴りではなく音で起きる。desire と decide のように綴りが近くても
/// 音が違うものは離れ、light と right のように綴りは違っても混同しやすいものは
/// 近づくようにする。
enum Phonetic {
    static func key(of word: String) -> String {
        var s = word.lowercased().filter { $0.isLetter }
        guard !s.isEmpty else { return "" }

        // 語頭の黙字
        for (from, to) in [("kn", "n"), ("gn", "n"), ("pn", "n"), ("wr", "r"), ("ps", "s")] {
            if s.hasPrefix(from) { s = to + String(s.dropFirst(2)); break }
        }
        if s.hasSuffix("mb") { s = String(s.dropLast()) }

        // つづりのかたまり。長いものから順に置き換える。
        let digraphs: [(String, String)] = [
            ("ough", "o"), ("augh", "af"), ("tion", "Sn"), ("sion", "Sn"),
            ("cia", "Sa"), ("tch", "C"), ("sch", "sk"), ("dge", "j"),
            ("sh", "S"), ("ch", "C"), ("th", "s"), ("ph", "f"),
            ("gh", ""), ("ck", "k"), ("qu", "kw"), ("wh", "w"), ("ng", "N"),
        ]
        for (from, to) in digraphs {
            s = s.replacingOccurrences(of: from, with: to)
        }

        var out = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            let next = i + 1 < chars.count ? chars[i+1] : " "
            switch ch {
            case "a", "e", "i", "o", "u", "y":
                out.append("a")                       // 母音はひとまとめ
            case "c":
                out.append("eiy".contains(next) ? "s" : "k")
            case "g":
                out.append("eiy".contains(next) ? "j" : "g")
            case "q": out.append("k")
            case "x": out.append("ks")
            case "z": out.append("s")
            case "v": out.append("b")                 // v と b は取り違えやすい
            case "l": out.append("r")                 // l と r も同じ扱いにする
            case "h": break                           // 語中の h はほぼ聞こえない
            default: out.append(ch)
            }
        }

        // 同じ音の連続をひとつにまとめる
        var collapsed = ""
        for ch in out where collapsed.last != ch {
            collapsed.append(ch)
        }
        return collapsed
    }
}
