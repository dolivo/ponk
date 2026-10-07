import Foundation

/// Oprava překlepů ve vyhledávání ("sroubvak" → "šroubovák", "akumulatr" → "akumulátor").
///
/// Slovník se staví ze slov v názvech produktů, značkách, kategoriích a parametrech.
/// Pro každé hledané slovo najde nejbližší slovo ve slovníku (Damerauova–Levenshteinova
/// vzdálenost: záměna, vynechání, přidání a prohození sousedních písmen). Záměna i/y
/// je levnější, protože je to v češtině nejčastější chyba. Funguje i pro začátek slova
/// ("srubov" → "šroubov…"), takže stačí napsat část.
struct Speller {
    struct Word {
        let key: [UInt8]      // bez diakritiky, malá písmena
        let display: [Character]  // jak se slovo píše v názvech produktů
        let freq: Int
    }

    struct Match {
        let word: String      // slovo bez diakritiky (pro hledání)
        let display: String   // s diakritikou (pro zobrazení)
        let cost: Int
        let freq: Int
    }

    private(set) var words: [Word] = []
    private var known: Set<String> = []

    /// - Parameter texts: texty produktů (název, značka, kategorie, parametry), každý jednou.
    /// Ze slovníku připraveného na GitHubu (tabulka vocab v datech) – rychlé načtení.
    init(entries: [(word: String, display: String, freq: Int)]) {
        words.reserveCapacity(entries.count)
        for e in entries {
            let chars = e.display.count == e.word.utf8.count ? Array(e.display) : Array(e.word)
            words.append(Word(key: Array(e.word.utf8), display: chars, freq: e.freq))
        }
        known = Set(entries.map(\.word))
    }

    /// Záloha pro starší data bez slovníku: postaví ho z textů produktů v telefonu.
    init(texts: [String], fold: (String) -> String) {
        var count: [String: Int] = [:]
        var display: [String: [Substring: Int]] = [:]
        for text in texts {
            let lower = text.lowercased()
            // fold jednou na celý text (rychlé); slova se spárují podle pořadí
            let originals = Self.tokenize(lower)
            let keys = Self.tokenize(fold(lower))
            let paired = originals.count == keys.count
            for (i, key) in keys.enumerated() where key.utf8.count >= 3 {
                if key.allSatisfy(\.isNumber) { continue }
                let k = String(key)
                count[k, default: 0] += 1
                display[k, default: [:]][paired ? originals[i] : key, default: 0] += 1
            }
        }
        words.reserveCapacity(count.count)
        for (key, n) in count {
            let shown = display[key]?.max { $0.value < $1.value }?.key ?? Substring(key)
            // diakritika se zobrazuje jen když sedí počet znaků (pro opravu začátku slova)
            let chars = shown.count == key.utf8.count ? Array(shown) : Array(key)
            words.append(Word(key: Array(key.utf8), display: chars, freq: n))
        }
        known = Set(count.keys)
    }

    static func tokenize(_ s: String) -> [Substring] {
        s.split { !($0.isLetter || $0.isNumber) }
    }

    func contains(_ folded: String) -> Bool { known.contains(folded) }

    /// Povolená „cena“ chyb podle délky slova (1 chyba = 2, záměna i/y = 1).
    static func budget(_ length: Int) -> Int {
        switch length {
        case ..<4: return 0
        case 4...5: return 2
        case 6...11: return 3
        default: return 4
        }
    }

    /// Nejbližší slovo ve slovníku, nebo nil, když nic není dost blízko.
    func correct(_ token: String) -> Match? {
        let t = Array(token.utf8)
        let limit = Self.budget(t.count)
        guard limit > 0 else { return nil }
        var best: (cost: Int, freq: Int, word: Word, cut: Int)?
        var prev = [Int](repeating: 0, count: 64), cur = prev, prev2 = prev
        for w in words {
            let k = w.key
            // celé slovo nemůže být o víc kratší; delší slova se porovnávají i jako začátek
            if k.count + limit / 2 < t.count { continue }
            let n = min(k.count, t.count + 2)
            if n >= 63 || t.count >= 63 { continue }
            for j in 0...n { prev[j] = j * 2 }
            var rowMin = 0
            for i in 1...t.count {
                cur[0] = i * 2
                rowMin = cur[0]
                for j in 1...n {
                    let a = t[i - 1], b = k[j - 1]
                    var sub = a == b ? 0 : 2
                    if sub == 2, (a == 105 && b == 121) || (a == 121 && b == 105) { sub = 1 } // i ↔ y
                    var v = min(prev[j - 1] + sub, prev[j] + 2, cur[j - 1] + 2)
                    if i > 1, j > 1, a == k[j - 2], t[i - 2] == b { v = min(v, prev2[j - 2] + 2) }
                    cur[j] = v
                    rowMin = min(rowMin, v)
                }
                if rowMin > limit + 1 { break }
                (prev2, prev, cur) = (prev, cur, prev2)
            }
            if rowMin > limit + 1 { continue }
            // prev = poslední řádek: vzdálenost tokenu od každého začátku slova
            var cost = n == k.count ? prev[n] : Int.max
            var cut = k.count
            let lo = max(1, t.count - 1), hi = min(n, t.count + 1)
            if lo <= hi {
                for j in lo...hi where j < k.count && prev[j] + 1 < cost { cost = prev[j] + 1; cut = j }
            }
            if k.first != t.first { cost += 1 } // první písmeno se plete málokdy
            guard cost > 0, cost <= limit else { continue }
            if let b = best, (b.cost, -b.freq) <= (cost, -w.freq) { continue }
            best = (cost, w.freq, w, cut)
        }
        guard let b = best else { return nil }
        let word = String(decoding: b.word.key.prefix(b.cut), as: UTF8.self)
        let display = String(b.word.display.prefix(b.cut))
        return Match(word: word, display: display, cost: b.cost, freq: b.freq)
    }
}
