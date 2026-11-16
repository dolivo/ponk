import Foundation

/// Vyhledávací texty všech produktů v jednom souvislém bloku paměti.
///
/// Hledání slova je jeden průchod blokem funkcí `memmem` ze systémové knihovny – ta je
/// psaná v assembleru a používá vektorové instrukce procesoru (NEON), takže projde
/// desítky megabajtů za pár milisekund. Dřív se každé slovo hledalo v databázi přes
/// LIKE řádek po řádku (a to několikrát na jedno hledání).
///
/// Texty jsou už bez diakritiky a malými písmeny (stejně jako hledaná slova), takže
/// porovnání po bajtech dává stejný výsledek jako LIKE '%slovo%'. Řádky jsou oddělené
/// znakem konce řádku, který se v hledaném slově nevyskytuje – shoda tak nikdy
/// nepřesáhne z jednoho produktu do druhého.
final class SearchIndex {
    /// rowid produktu pro každý řádek (vzestupně)
    private(set) var ids: ContiguousArray<Int64> = []
    /// začátek textu řádku v bloku; o jeden prvek delší (konec posledního řádku)
    private var starts: ContiguousArray<Int32> = [0]
    private var bytes: ContiguousArray<UInt8> = []

    var count: Int { ids.count }

    init(capacity: Int = 0, rows: Int = 0) {
        bytes.reserveCapacity(capacity)
        ids.reserveCapacity(rows)
        starts.reserveCapacity(rows + 1)
    }

    /// Přidá další řádek; `id` musí být větší než předchozí.
    func append(id: Int64, text: UnsafeBufferPointer<UInt8>) {
        bytes.append(contentsOf: text)
        bytes.append(0x0A)
        ids.append(id)
        starts.append(Int32(bytes.count))
    }

    /// Jde hledat přímo v paměti? Znaky _ a % mají v LIKE zvláštní význam, taková
    /// (vzácná) slova se dál hledají v databázi, aby se výsledek nelišil.
    static func isPlain(_ needle: String) -> Bool {
        !needle.isEmpty && !needle.utf8.contains { $0 == 0x5F || $0 == 0x25 || $0 == 0x0A }
    }

    /// Řádek, do kterého patří pozice v bloku (půlení intervalu).
    private func row(at offset: Int) -> Int {
        var lo = 0, hi = ids.count - 1
        let o = Int32(offset)
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if starts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Indexy řádků (vzestupně), které obsahují `needle`.
    func rows(containing needle: String) -> ContiguousArray<Int32> {
        var out = ContiguousArray<Int32>()
        let n = Array(needle.utf8)
        guard !n.isEmpty, !ids.isEmpty else { return out }
        bytes.withUnsafeBufferPointer { hay in
            n.withUnsafeBufferPointer { nb in
                guard let base = hay.baseAddress, let needleBase = nb.baseAddress else { return }
                var pos = 0
                let total = hay.count
                while pos < total, let hit = memmem(base + pos, total - pos, needleBase, nb.count) {
                    let offset = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                    let r = row(at: offset)
                    out.append(Int32(r))
                    pos = Int(starts[r + 1])   // další shodu hledat až v následujícím řádku
                }
            }
        }
        return out
    }

    /// Z daných řádků nechá jen ty, které obsahují i `needle` (další slovo dotazu).
    func filter(_ rows: ContiguousArray<Int32>, containing needle: String) -> ContiguousArray<Int32> {
        var out = ContiguousArray<Int32>()
        let n = Array(needle.utf8)
        guard !n.isEmpty else { return rows }
        out.reserveCapacity(rows.count)
        bytes.withUnsafeBufferPointer { hay in
            n.withUnsafeBufferPointer { nb in
                guard let base = hay.baseAddress, let needleBase = nb.baseAddress else { return }
                for r in rows {
                    let start = Int(starts[Int(r)]), end = Int(starts[Int(r) + 1]) - 1
                    if end - start >= nb.count, memmem(base + start, end - start, needleBase, nb.count) != nil {
                        out.append(r)
                    }
                }
            }
        }
        return out
    }

    /// Indexy řádků pro dané rowid (pro slova hledaná v databázi přes LIKE).
    func rows(forIDs sorted: [Int64]) -> ContiguousArray<Int32> {
        var out = ContiguousArray<Int32>()
        out.reserveCapacity(sorted.count)
        var lo = 0
        for id in sorted {
            var l = lo, h = ids.count
            while l < h {
                let mid = (l + h) >> 1
                if ids[mid] < id { l = mid + 1 } else { h = mid }
            }
            if l < ids.count, ids[l] == id { out.append(Int32(l)); lo = l + 1 }
        }
        return out
    }
}

/// Rychlé odstranění diakritiky a převod na malá písmena pro vyhledávací texty.
///
/// Výsledek je stejný jako `LocalEngine.fold` (Foundation), jen se nepočítá pro celý text
/// znovu: každý znak se přes Foundation převede jednou a příště se vezme z tabulky.
/// Platí to pro znaky, jejichž převod nezávisí na sousedech (latinka s diakritikou,
/// interpunkce, značky). Jakmile text obsahuje cokoli jiného (např. samostatná kombinující
/// znaménka nebo jiná písma), převede se celý původní cestou.
struct FastFold {
    private var ascii: [[UInt8]] = []
    /// Když se každý ASCII znak převádí na právě jeden bajt (běžný případ), stačí jednoduchá tabulka.
    private var asciiByte: [UInt8]?
    private var table: [UInt32: [UInt8]] = [:]

    init() {
        ascii = (0..<128).map { Array(LocalEngine.fold(String(UnicodeScalar(UInt8($0)))).utf8) }
        if ascii.allSatisfy({ $0.count == 1 }) { asciiByte = ascii.map { $0[0] } }
    }

    private static func isContextFree(_ v: UInt32) -> Bool {
        (0x00A0...0x02FF).contains(v)
            || ((0x2000...0x23FF).contains(v) && v != 0x200C && v != 0x200D && !(0x20D0...0x20FF).contains(v))
    }

    /// Připojí převedený text na konec `out`.
    mutating func fold(_ s: String, into out: inout ContiguousArray<UInt8>) {
        let mark = out.count
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 128 {
                if let asciiByte { out.append(asciiByte[Int(v)]) } else { out.append(contentsOf: ascii[Int(v)]) }
            } else if Self.isContextFree(v) {
                if let hit = table[v] {
                    out.append(contentsOf: hit)
                } else {
                    let folded = Array(LocalEngine.fold(String(scalar)).utf8)
                    table[v] = folded
                    out.append(contentsOf: folded)
                }
            } else {
                // vzácný případ: celý text původní cestou
                out.removeSubrange(mark...)
                out.append(contentsOf: LocalEngine.fold(s).utf8)
                return
            }
        }
    }
}
