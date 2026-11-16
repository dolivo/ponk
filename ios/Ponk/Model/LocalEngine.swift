import Foundation
import SQLite3

/// Data v telefonu: stažená databáze (ceny, sklady, historie) + vlastní databáze
/// uživatele (hlídané, uložená hledání, nastavení). Odpovídá stejnými JSON strukturami
/// jako dřív server na počítači, takže obrazovky aplikace se nemusely měnit.
actor LocalEngine {
    static let labels: [String: String] = [
        "sell_off": "Výprodej", "sale": "Akce", "free_shipping": "Doprava zdarma", "only_online": "Jen online",
        "warranty": "Prodloužená záruka", "qty_discount": "Množstevní sleva", "new": "Novinka",
        "gift": "Dárek k nákupu", "promo": "Akce výrobce",
    ]
    static let labelOrder = ["gift", "promo", "sell_off", "sale", "free_shipping", "only_online", "warranty", "qty_discount", "new"]
    static let pageSize = 30

    private var db: SQLiteDB?
    /// Seznamy pro našeptávač (kategorie a značky se mění jen s novými daty).
    private var suggestIndex: SuggestIndex?
    private let dataPath: String
    private let userPath: String

    init(dataPath: String, userPath: String) {
        self.dataPath = dataPath
        self.userPath = userPath
    }

    var hasData: Bool { db != nil }

    /// Co stažená data obsahují (starší data z GitHubu nemusí mít nové tabulky).
    private struct Caps { var active = false; var restock = false; var maps = false; var ratingCount = false; var extras = false
        var platforms = false; var psearch = false }
    private var caps = Caps()

    /// Vyhledávací texty v paměti (načtou se při prvním hledání) a co je právě v pomocné tabulce temp.hits.
    private var searchIndex: SearchIndex?
    private var hitsKey: String?
    private var lastMatch: (key: String, rows: ContiguousArray<Int32>, counts: [UInt8]?)?
    /// Výsledky, které se mezi staženími dat nemění: počty produktů pro filtr, kategorie, názvy parametrů.
    private var countCache: [String: Int] = [:]
    private var facetsCache: [String: [String: Any]] = [:]
    private var categoriesCache: [String: [String: Any]] = [:]
    private var attrLabels: [String: String]?
    private var platformDefs: [[String: Any]]?
    private var itemColsSQL = ""

    private func resetCaches() {
        suggestIndex = nil
        speller = nil
        resolved = [:]
        searchIndex = nil
        hitsKey = nil
        lastMatch = nil
        countCache = [:]
        facetsCache = [:]
        categoriesCache = [:]
        attrLabels = nil
        platformDefs = nil
    }

    // MARK: - otevření a příprava dat

    func open() throws {
        db?.close()
        db = nil
        let user = try SQLiteDB(path: userPath)
        try user.exec("""
            CREATE TABLE IF NOT EXISTS watch(sku TEXT PRIMARY KEY, added TEXT, added_price REAL, target REAL, notified_price REAL);
            CREATE TABLE IF NOT EXISTS saved(id INTEGER PRIMARY KEY, name TEXT, query TEXT, created TEXT, checked TEXT);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT);
            INSERT OR IGNORE INTO settings VALUES('store', '888');
            CREATE TABLE IF NOT EXISTS lists(id INTEGER PRIMARY KEY, name TEXT, created TEXT, store TEXT);
            CREATE TABLE IF NOT EXISTS list_items(id INTEGER PRIMARY KEY, list_id INTEGER, sku TEXT, text TEXT,
                qty REAL DEFAULT 1, checked INTEGER DEFAULT 0, note TEXT, added TEXT, added_price REAL);
            CREATE INDEX IF NOT EXISTS list_items_list ON list_items(list_id);
            CREATE TABLE IF NOT EXISTS purchases(sku TEXT, day TEXT, kind TEXT, ref TEXT, qty REAL, PRIMARY KEY(sku, ref));
            INSERT INTO lists(name, created) SELECT 'Nákupní seznam', date('now') WHERE NOT EXISTS (SELECT 1 FROM lists);
            """)
        try? user.exec("ALTER TABLE watch ADD COLUMN notified_restock TEXT")
        try? user.exec("ALTER TABLE lists ADD COLUMN share_id TEXT")
        user.close()
        guard FileManager.default.fileExists(atPath: dataPath) else { return }
        let d = try SQLiteDB(path: dataPath)
        // Rychlejší čtení: větší mezipaměť stránek, dočasné tabulky v paměti, soubor mapovaný do paměti.
        try? d.exec("PRAGMA cache_size = -16000; PRAGMA temp_store = MEMORY; PRAGMA mmap_size = 268435456;")
        // Data stažená starší verzí aplikace: jednorázově doplní nové indexy a vyhledávací tabulku.
        try Self.upgrade(d)
        try d.run("ATTACH DATABASE ? AS u", [userPath])
        let cols = Set(try d.query("PRAGMA table_info(products)").compactMap { $0["name"] as? String })
        let tables = Set(try d.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"] as? String })
        caps = Caps(active: cols.contains("active"), restock: tables.contains("restock"), maps: tables.contains("store_maps"),
                    ratingCount: cols.contains("rating_count"), extras: tables.contains("extras") && tables.contains("banners"),
                    platforms: tables.contains("platforms"), psearch: tables.contains("psearch"))
        try d.exec("CREATE TEMP TABLE IF NOT EXISTS hits(id INTEGER PRIMARY KEY, n INTEGER)")
        db = d
        resetCaches()
        itemColsSQL = Self.baseItemCols + (caps.active ? ", p.active, p.last_price" : ", 1 AS active, NULL AS last_price")
            + (caps.ratingCount ? ", p.rating_count" : ", NULL AS rating_count")
            + (caps.platforms ? ", (SELECT x.body FROM platforms x WHERE x.sku = p.sku) AS body_only" : ", NULL AS body_only")
    }

    func closeData() {
        db?.close()
        db = nil
        resetCaches()
    }

    /// Verze přípravy dat v telefonu (PRAGMA user_version). Starší data se při otevření doplní.
    private static let preparedVersion = 2

    /// Po stažení: doplní vyhledávací texty a indexy (v souboru nejsou kvůli velikosti).
    static func prepareDownloaded(path: String) throws {
        let d = try SQLiteDB(path: path)
        defer { d.close() }
        // Soubor se teprve připravuje (při chybě se stáhne znovu), takže není potřeba žurnál ani fsync.
        try? d.exec("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA cache_size = -32000; PRAGMA temp_store = MEMORY;")
        try buildSearchText(d)
        try buildIndexes(d)
        try d.exec("PRAGMA user_version = \(preparedVersion)")
    }

    /// Doplní to, co starší verze aplikace v datech nepřipravila (jednou po aktualizaci aplikace).
    private static func upgrade(_ d: SQLiteDB) throws {
        let version = (try d.scalar("PRAGMA user_version") as? Int) ?? 0
        guard version < preparedVersion else { return }
        let tables = Set(try d.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"] as? String })
        guard tables.contains("products") else { return }
        // Verze se zapíše až na konci, takže přerušená příprava se příště provede celá znovu.
        let cols = try d.query("PRAGMA table_info(products)").compactMap { $0["name"] as? String }
        if cols.contains("search") {
            // text už starší verze připravila ve sloupci products.search – jen se přesune do úzké tabulky
            try d.transaction {
                try d.exec("""
                    DROP TABLE IF EXISTS psearch;
                    CREATE TABLE psearch(id INTEGER PRIMARY KEY, text TEXT);
                    INSERT INTO psearch SELECT rowid, search FROM products WHERE price IS NOT NULL AND search IS NOT NULL ORDER BY rowid;
                    """)
            }
        } else {
            try buildSearchText(d)
        }
        try buildIndexes(d)
        try d.exec("PRAGMA user_version = \(preparedVersion)")
    }

    /// Klíčová slova: kromě názvu, značky a kategorie se hledá i v parametrech ("li-ion", "18 v", "dub").
    /// Text je bez diakritiky a malými písmeny, v úzké tabulce mimo products (tabulka produktů
    /// tak zůstává malá a její procházení rychlé).
    private static func buildSearchText(_ d: SQLiteDB) throws {
        var folder = FastFold()
        var ids = ContiguousArray<Int64>()
        var ends = ContiguousArray<Int>()
        var bytes = ContiguousArray<UInt8>()
        bytes.reserveCapacity(16 << 20)
        var text = ""
        try d.each("""
            SELECT p.rowid, p.name, p.brand, p.cat2, p.cat3, p.sku, p.ean,
                   (SELECT GROUP_CONCAT(av.value, ' ') FROM product_attrs pa JOIN attr_values av ON av.id = pa.vid
                    WHERE pa.sku = p.sku) AS params
            FROM products p WHERE p.price IS NOT NULL ORDER BY p.rowid
            """) { stmt in
            text.removeAll(keepingCapacity: true)
            var first = true
            for col in 1...7 where sqlite3_column_type(stmt, Int32(col)) == SQLITE_TEXT {
                guard let c = sqlite3_column_text(stmt, Int32(col)) else { continue }
                if !first { text.append(" ") }
                first = false
                text.append(String(cString: c))
            }
            folder.fold(text, into: &bytes)
            ids.append(sqlite3_column_int64(stmt, 0))
            ends.append(bytes.count)
        }
        try d.transaction {
            try d.exec("DROP TABLE IF EXISTS psearch; CREATE TABLE psearch(id INTEGER PRIMARY KEY, text TEXT);")
            var i = 0
            try bytes.withUnsafeBufferPointer { all in
                try d.insertText("INSERT INTO psearch(id, text) VALUES(?, ?)") {
                    guard i < ids.count else { return nil }
                    let start = i == 0 ? 0 : ends[i - 1]
                    defer { i += 1 }
                    return (ids[i], UnsafeBufferPointer(rebasing: all[start..<ends[i]]))
                }
            }
        }
    }

    /// Indexy pro nejčastější pohledy: řazení bez třídění celé tabulky a počítání filtrů jen z indexu.
    private static func buildIndexes(_ d: SQLiteDB) throws {
        try d.exec("""
            DROP INDEX IF EXISTS p_cat;
            DROP INDEX IF EXISTS p_brand;
            DROP INDEX IF EXISTS p_disc;
            DROP INDEX IF EXISTS stock_store;
            CREATE INDEX IF NOT EXISTS p_cat2 ON products(cat1, cat2, cat3, brand, labels, price);
            CREATE INDEX IF NOT EXISTS p_brand2 ON products(brand, price);
            CREATE INDEX IF NOT EXISTS p_labels ON products(labels) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS p_price ON products(price);
            CREATE INDEX IF NOT EXISTS p_rel ON products(rank DESC, COALESCE(real_discount, 0) DESC, name, sku) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS p_disc2 ON products(COALESCE(real_discount, 0) DESC, COALESCE(drop_pct, 0) DESC, sku) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS p_changed ON products(price_changed_at);
            CREATE INDEX IF NOT EXISTS p_seen ON products(first_seen DESC, rank DESC, sku) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS p_created ON products(created DESC, sku) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS p_catrank ON products(cat1, rank DESC, sku) WHERE price IS NOT NULL;
            CREATE INDEX IF NOT EXISTS pa_vid ON product_attrs(vid, sku);
            CREATE INDEX IF NOT EXISTS av_code ON attr_values(code, value);
            ANALYZE;
            """)
    }

    private static let czech = Locale(identifier: "cs_CZ")

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: czech).lowercased()
    }

    // MARK: - směrování (stejné cesty jako REST API serveru)

    /// Totéž co handle(), ale vrací rovnou JSON (bezpečné předávání mezi vlákny).
    func handleJSON(method: String, path: String, query: [String: String], body: Data?) throws -> Data {
        let b = try body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return try JSONSerialization.data(withJSONObject: try handle(method: method, path: path, query: query, body: b))
    }

    private let decoder = JSONDecoder()

    /// Vyřídí dotaz a odpověď rovnou převede na typ pro obrazovku. Převod běží tady v jádru
    /// (mimo hlavní vlákno), takže rozhraní při načítání nezadrhává.
    func handleDecoded<T: Decodable>(_ type: T.Type, path: String, query: [String: String]) throws -> T {
        try decoder.decode(T.self, from: try handleJSON(method: "GET", path: path, query: query, body: nil))
    }

    func handle(method: String, path: String, query: [String: String], body: [String: Any]?) throws -> Any {
        let parts = path.split(separator: "/").map(String.init)
        let head = parts.first ?? ""
        let user = try userDB()
        switch (method, head) {
        case ("GET", "meta"): return try meta()
        case ("POST", "settings"):
            for (k, v) in body ?? [:] where ["store", "auto_wifi", "repo"].contains(k) {
                try user.run("INSERT OR REPLACE INTO \(t("settings")) VALUES(?, ?)", [k, "\(v)"])
            }
            return ["ok": true]
        case ("GET", "watch"): return ["items": try watchItems()]
        case ("GET", "widget"): return try widgetSnapshot(listID: query["list"].flatMap(Int.init))
        case ("POST", "watch"):
            let sku = body?["sku"] as? String ?? ""
            let price = try data().scalar("SELECT price FROM products WHERE sku = ?", [sku])
            // keep: rychlé hlídání z nabídky dlaždice nepřepíše už hlídaný produkt (datum a cenu od kdy)
            let verb = (body?["keep"] as? Bool ?? false) ? "INSERT OR IGNORE" : "INSERT OR REPLACE"
            try user.run("\(verb) INTO \(t("watch"))(sku, added, added_price, target, notified_price) VALUES(?, ?, ?, ?, NULL)",
                         [sku, Self.today(), price, body?["target"] as? Double ?? (body?["target"] as? Int).map(Double.init)])
            return ["ok": true]
        case ("DELETE", "watch"):
            try user.run("DELETE FROM \(t("watch")) WHERE sku = ?", [parts.count > 1 ? parts[1] : ""])
            return ["ok": true]
        case (_, "lists"), (_, "list"), (_, "listitem"), ("GET", "inlists"), (_, "listshare"):
            return try shoppingList(method: method, parts: parts, query: query, body: body)
        case ("GET", "saved"): return ["items": try savedItems()]
        case ("POST", "purchases"):
            // koupené produkty z účtu Bauhaus (objednávky a rezervace); nahradí předchozí stav
            try user.run("DELETE FROM \(t("purchases"))")
            for r in body?["items"] as? [[String: Any]] ?? [] {
                guard let sku = r["sku"] as? String else { continue }
                try user.run("INSERT OR REPLACE INTO \(t("purchases")) VALUES(?, ?, ?, ?, ?)",
                             [sku, r["day"] as? String, r["kind"] as? String, r["ref"] as? String, num(r["qty"])])
            }
            return ["ok": true]
        case ("POST", "saved"):
            let q = body?["query"] as? [String: Any] ?? [:]
            let json = String(data: try JSONSerialization.data(withJSONObject: q), encoding: .utf8) ?? "{}"
            try user.run("INSERT INTO \(t("saved"))(name, query, created, checked) VALUES(?, ?, ?, ?)",
                         [body?["name"] as? String ?? "Hledání", json, Self.today(), Self.today()])
            return ["ok": true]
        case ("DELETE", "saved"):
            if parts.count > 2, parts[2] == "seen" {
                try user.run("UPDATE \(t("saved")) SET checked = ? WHERE id = ?", [Self.today(), Int(parts[1]) ?? -1])
            } else {
                try user.run("DELETE FROM \(t("saved")) WHERE id = ?", [Int(parts.count > 1 ? parts[1] : "") ?? -1])
            }
            return ["ok": true]
        default: break
        }
        _ = try data()
        switch head {
        case "home": return try home()
        case "search": return try search(query)
        case "suggest": return try suggest(query["q"] ?? "")
        case "items": return ["items": try itemsBySKU(many(query, "skus"))]
        case "platforms": return ["items": try platformList()]
        case "ean": return ["items": try itemsByEAN(parts.count > 1 ? parts[1] : "")]
        case "storemap":
            guard parts.count > 1, let m = try storeMap(parts[1]) else { throw EngineError.notFound }
            return m
        case "categories": return try categories(query)
        case "product":
            guard parts.count > 1, let p = try product(parts[1]) else { throw EngineError.notFound }
            return p
        default: throw EngineError.notFound
        }
    }

    enum EngineError: LocalizedError {
        case noData, notFound
        var errorDescription: String? {
            switch self {
            case .noData: return "Data ještě nejsou stažená. Otevři Více a stáhni je."
            case .notFound: return "Nenalezeno."
            }
        }
    }

    private func data() throws -> SQLiteDB {
        guard let db else { throw EngineError.noData }
        return db
    }

    private var userDBHandle: SQLiteDB?
    private func userDB() throws -> SQLiteDB {
        if let db { return db } // uživatelská databáze je připojená jako "u"
        if let userDBHandle { return userDBHandle }
        let u = try SQLiteDB(path: userPath)
        userDBHandle = u
        return u
    }

    private func t(_ table: String) -> String { db != nil ? "u.\(table)" : table }

    func setting(_ key: String) -> String? {
        (try? userDB().scalar("SELECT value FROM \(t("settings")) WHERE key = ?", [key])) as? String
    }

    func info(_ key: String) -> String? {
        (try? db?.scalar("SELECT value FROM info WHERE key = ?", [key])) as? String
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func today() -> String { dayFormatter.string(from: Date()) }

    // MARK: - meta

    private func meta() throws -> [String: Any] {
        let store = setting("store") ?? "888"
        var settings: [String: String] = ["store": store]
        if let v = setting("auto_wifi") { settings["auto_wifi"] = v }
        var out: [String: Any] = [
            "settings": settings, "labels": Self.labels, "stores": [], "products": 0, "watched_drops": 0,
            "sync": ["running": false, "phase": "", "done": 0, "total": 0, "message": ""],
        ]
        guard let db else { return out }
        out["stores"] = try db.query("SELECT code, name, city FROM stores ORDER BY name")
        out["products"] = try db.scalar("SELECT COUNT(*) FROM products") ?? 0
        if let lc = info("last_change"), !lc.isEmpty { out["last_change"] = lc }
        out["last_run"] = ["id": 1, "finished": info("last_run") ?? "", "started": info("generated_at") ?? ""]
        out["watched_drops"] = try db.scalar("""
            SELECT COUNT(*) FROM u.watch w CROSS JOIN products p ON p.sku = w.sku
            WHERE p.price < w.added_price OR (w.target IS NOT NULL AND p.price <= w.target)
            """) ?? 0
        if let v = info("server_version") { out["version"] = v }
        return out
    }

    // MARK: - filtry (port ponk/search.py → build_where)

    private func many(_ q: [String: String], _ key: String) -> [String] {
        (q[key] ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    private func buildWhere(_ q: [String: String], skip: Set<String> = []) throws -> (String, [Any?]) {
        var w = ["p.price IS NOT NULL"]
        var a: [Any?] = []
        let r = resolve(q)
        if !r.tokens.isEmpty, caps.psearch {
            // slova se najdou v paměti a odpovídající produkty čekají v pomocné tabulce
            try ensureHits(tokens: r.tokens, any: r.any)
            w.append(Self.hitsClause)
        } else if r.any, !r.tokens.isEmpty {
            w.append("(" + r.tokens.map { _ in "p.search LIKE ?" }.joined(separator: " OR ") + ")")
            a += r.tokens.map { "%\($0)%" }
        } else {
            for tok in r.tokens { w.append("p.search LIKE ?"); a.append("%\(tok)%") }
        }
        if !skip.contains("cat") {
            for key in ["cat1", "cat2", "cat3"] { if let v = q[key], !v.isEmpty { w.append("p.\(key) = ?"); a.append(v) } }
        }
        let brands = many(q, "brand")
        if !brands.isEmpty, !skip.contains("brand") {
            w.append("p.brand IN (\(Array(repeating: "?", count: brands.count).joined(separator: ",")))"); a += brands
        }
        if !skip.contains("price") {
            if let v = q["pmin"].flatMap(Double.init) { w.append("p.price >= ?"); a.append(v) }
            if let v = q["pmax"].flatMap(Double.init) { w.append("p.price <= ?"); a.append(v) }
        }
        if let v = q["disc"].flatMap(Int.init) { w.append("COALESCE(p.real_discount, 0) >= ?"); a.append(v) }
        if !skip.contains("label") {
            for lab in many(q, "label") where Self.labels[lab] != nil { w.append("p.labels LIKE ?"); a.append("%,\(lab),%") }
        }
        if q["online"] == "1" { w.append("p.online_in_stock = 1") }
        if let store = q["store"], !store.isEmpty, !skip.contains("store") {
            w.append("EXISTS (SELECT 1 FROM stock s WHERE s.sku = p.sku AND s.store = ? AND s.qty > 0)"); a.append(store)
        }
        if let v = q["rating"].flatMap(Int.init) { w.append("p.rating >= ?"); a.append(v * 20) }
        if let v = q["drop_days"].flatMap(Int.init) {
            let since = Calendar.current.date(byAdding: .day, value: -v, to: Date()) ?? Date()
            w.append("p.price_changed_at >= ? AND p.drop_pct > 0"); a.append(Self.dayFormatter.string(from: since))
        }
        if let v = q["drop_min"].flatMap(Double.init) { w.append("p.drop_pct >= ?"); a.append(v) }
        if q["unit"] == "1" { w.append("p.unit_price IS NOT NULL") }
        if let v = q["since"], !v.isEmpty {
            w.append("(p.first_seen > ? OR (p.price_changed_at > ? AND p.drop_pct > 0))"); a += [v, v]
        }
        if q["watch"] == "1" { w.append("p.sku IN (SELECT sku FROM u.watch)") }
        // akumulátorové platformy: „k mým bateriím“ a „jen tělo bez akumulátoru“
        if caps.platforms {
            let plats = many(q, "plat")
            if !plats.isEmpty {
                w.append("p.sku IN (SELECT sku FROM platforms WHERE platform IN (\(Array(repeating: "?", count: plats.count).joined(separator: ","))))")
                a += plats
            }
            if q["body"] == "1" { w.append("p.sku IN (SELECT sku FROM platforms WHERE body = 1)") }
        }
        if let v = q["restock_days"].flatMap(Int.init), caps.restock {
            let since = Self.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -v, to: Date()) ?? Date())
            if let store = q["store"], !store.isEmpty {
                w.append("EXISTS (SELECT 1 FROM restock r WHERE r.sku = p.sku AND r.store = ? AND r.day > ?)"); a += [store, since]
            } else {
                w.append("EXISTS (SELECT 1 FROM restock r WHERE r.sku = p.sku AND r.day > ?)"); a.append(since)
            }
        }
        if let v = q["new_days"].flatMap(Int.init) {
            let since = Self.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -v, to: Date()) ?? Date())
            w.append("p.first_seen > ? AND p.first_seen > ?"); a += [since, info("first_day") ?? "9999"]
        }
        for key in q.keys.sorted() where key.hasPrefix("a_") {
            let code = String(key.dropFirst(2))
            let vals = many(q, key)
            if vals.isEmpty || skip.contains(code) { continue }
            w.append("p.sku IN (SELECT pa.sku FROM product_attrs pa JOIN attr_values av ON av.id = pa.vid "
                     + "WHERE av.code = ? AND av.value IN (\(Array(repeating: "?", count: vals.count).joined(separator: ","))))")
            a.append(code)
            a += vals
        }
        return (w.joined(separator: " AND "), a)
    }

    private static let sorts: [String: String] = [
        "relevance": "p.rank DESC, COALESCE(p.real_discount, 0) DESC, p.name, p.sku",
        "price_asc": "p.price ASC, p.sku",
        "price_desc": "p.price DESC, p.sku",
        "discount": "COALESCE(p.real_discount, 0) DESC, COALESCE(p.drop_pct, 0) DESC, p.sku",
        "drop": "(p.price_changed_at IS NOT NULL AND p.drop_pct > 0) DESC, p.price_changed_at DESC, p.drop_pct DESC, p.sku",
        "unit": "p.unit_price IS NULL, p.unit_price ASC, p.sku",
        "rating": "COALESCE(p.rating, 0) DESC, p.sku",
        "newest": "p.created DESC, p.sku",
        "newest_seen": "p.first_seen DESC, p.rank DESC, p.sku",
    ]

    private static let baseItemCols = """
        p.sku, p.name, p.brand, p.image, p.price, p.was_price, p.min30_price, p.real_discount, p.labels,
        p.online_in_stock, p.unit_price, p.unit, p.rating, p.prev_price, p.price_changed_at, p.drop_pct, p.cat3, p.dims
        """

    private var itemCols: String { itemColsSQL }

    private func itemsFor(_ rows: [[String: Any]], store: String?) throws -> [[String: Any]] {
        guard !rows.isEmpty else { return [] }
        var qty: [String: Any] = [:]
        if let store {
            let skus = rows.compactMap { $0["sku"] as? String }
            for r in try data().query("SELECT sku, qty FROM stock WHERE store = ? AND sku IN (\(Array(repeating: "?", count: skus.count).joined(separator: ",")))",
                                      [store] + skus) {
                if let s = r["sku"] as? String { qty[s] = r["qty"] }
            }
        }
        return rows.map { r in
            var r = r
            r["labels"] = ((r["labels"] as? String) ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
            r["store_qty"] = qty[r["sku"] as? String ?? ""] ?? 0
            return r
        }
    }

    // MARK: - klíčová slova a oprava překlepů

    struct Resolved {
        var tokens: [String] = []
        /// Opravený dotaz k zobrazení ("Zobrazuji výsledky pro …"), nil když nebylo co opravit.
        var corrected: String?
        /// Žádný produkt neobsahuje všechna slova → stačí kterékoli (řadí se podle počtu shod).
        var any = false
    }

    private var speller: Speller?
    private var resolved: [String: Resolved] = [:]

    private static let tokenChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-+._")).inverted

    private func loadSpeller(_ db: SQLiteDB) throws -> Speller {
        if let speller { return speller }
        if (try? db.scalar("SELECT 1 FROM sqlite_master WHERE name = 'vocab'")) as? Int == 1 {
            let entries = try db.query("SELECT word, display, freq FROM vocab").compactMap { r -> (word: String, display: String, freq: Int)? in
                guard let w = r["word"] as? String else { return nil }
                return (w, r["display"] as? String ?? w, r["freq"] as? Int ?? 1)
            }
            let s = Speller(entries: entries)
            speller = s
            return s
        }
        var texts: [String] = []
        for r in try db.query("SELECT name, brand, cat2, cat3 FROM products WHERE price IS NOT NULL") {
            texts.append(["name", "brand", "cat2", "cat3"].compactMap { r[$0] as? String }.joined(separator: " "))
        }
        for r in try db.query("SELECT DISTINCT value FROM attr_values") { if let v = r["value"] as? String { texts.append(v) } }
        let s = Speller(texts: texts, fold: Self.fold)
        speller = s
        return s
    }

    /// Rozloží hledaný text na slova. Když nic neodpovídá, opraví slova s překlepem
    /// a případně přepne na „kterékoli slovo“. Parametr exact=1 opravu vypne.
    private func resolve(_ q: [String: String]) -> Resolved {
        let raw = (q["q"] ?? "").trimmingCharacters(in: .whitespaces)
        let tokens = Array(Self.fold(raw).components(separatedBy: Self.tokenChars).filter { !$0.isEmpty }.prefix(8))
        guard !tokens.isEmpty else { return Resolved() }
        if q["exact"] == "1" { return Resolved(tokens: tokens) }
        if let hit = resolved[raw] { return hit }
        let result = (try? computeResolve(raw: raw, tokens: tokens)) ?? Resolved(tokens: tokens)
        if resolved.count > 200 { resolved.removeAll() }
        resolved[raw] = result
        return result
    }

    private func count(_ tokens: [String], any: Bool = false) throws -> Int {
        if caps.psearch { return try match(tokens: tokens, any: any).rows.count }
        let w = tokens.map { _ in "search LIKE ?" }.joined(separator: any ? " OR " : " AND ")
        return (try data().scalar("SELECT COUNT(*) FROM products WHERE price IS NOT NULL AND (\(w))",
                                  tokens.map { "%\($0)%" }) as? Int) ?? 0
    }

    // MARK: - hledání slov v paměti

    private static let hitsClause = "p.rowid IN (SELECT id FROM temp.hits)"

    private func loadSearchIndex() throws -> SearchIndex {
        if let searchIndex { return searchIndex }
        let index = SearchIndex(capacity: 16 << 20, rows: 110_000)
        try data().each("SELECT id, text FROM psearch ORDER BY id") { stmt in
            let n = Int(sqlite3_column_bytes(stmt, 1))
            index.append(id: sqlite3_column_int64(stmt, 0), text: UnsafeBufferPointer(start: sqlite3_column_text(stmt, 1), count: n))
        }
        searchIndex = index
        return index
    }

    /// Řádky indexu obsahující slovo. Slova se znaky _ a % (v LIKE zástupné) hledá databáze, aby se výsledek nelišil.
    private func rows(matching token: String, in index: SearchIndex) throws -> ContiguousArray<Int32> {
        if SearchIndex.isPlain(token) { return index.rows(containing: token) }
        let ids = try data().query("SELECT id FROM psearch WHERE text LIKE ? ORDER BY id", ["%\(token)%"]).compactMap { ($0["id"] as? Int).map(Int64.init) }
        return index.rows(forIDs: ids)
    }

    /// Produkty obsahující všechna slova (nebo kterékoli, s počtem shod). Poslední výsledek se pamatuje,
    /// protože jedno hledání se ptá několikrát na totéž (počet, stránka, filtry).
    private func match(tokens: [String], any: Bool) throws -> (key: String, rows: ContiguousArray<Int32>, counts: [UInt8]?) {
        let key = (any ? "|" : "&") + tokens.joined(separator: "\n")
        if let lastMatch, lastMatch.key == key { return lastMatch }
        let index = try loadSearchIndex()
        var result: (key: String, rows: ContiguousArray<Int32>, counts: [UInt8]?)
        if any {
            var per = [UInt8](repeating: 0, count: index.count)
            for tok in tokens { for r in try rows(matching: tok, in: index) { per[Int(r)] &+= 1 } }
            var rows = ContiguousArray<Int32>()
            var counts: [UInt8] = []
            for (i, c) in per.enumerated() where c > 0 { rows.append(Int32(i)); counts.append(c) }
            result = (key, rows, counts)
        } else {
            var rows = try self.rows(matching: tokens[0], in: index)
            for tok in tokens.dropFirst() where !rows.isEmpty {
                if SearchIndex.isPlain(tok) {
                    rows = index.filter(rows, containing: tok)
                } else {
                    let other = Set(try self.rows(matching: tok, in: index))
                    rows = ContiguousArray(rows.filter { other.contains($0) })
                }
            }
            result = (key, rows, nil)
        }
        lastMatch = result
        return result
    }

    /// Naplní temp.hits produkty pro daná slova (jen když tam už nejsou z předchozího dotazu).
    private func ensureHits(tokens: [String], any: Bool) throws {
        let m = try match(tokens: tokens, any: any)
        try fillHits(key: m.key, rows: m.rows, counts: m.counts)
    }

    private func fillHits(key: String, rows: ContiguousArray<Int32>, counts: [UInt8]?) throws {
        if hitsKey == key { return }
        let db = try data()
        let index = try loadSearchIndex()
        hitsKey = nil
        try db.exec("DELETE FROM temp.hits")
        var ids = ContiguousArray<Int64>()
        ids.reserveCapacity(rows.count)
        for r in rows { ids.append(index.ids[Int(r)]) }
        try ids.withUnsafeBufferPointer { idp in
            if let counts {
                try counts.withUnsafeBufferPointer { cp in
                    try db.insertPairs("INSERT INTO temp.hits(id, n) VALUES(?, ?)", ids: idp, counts: cp)
                }
            } else {
                try db.insertPairs("INSERT INTO temp.hits(id) VALUES(?)", ids: idp, counts: nil)
            }
        }
        hitsKey = key
    }

    private static func cacheKey(_ w: String, _ a: [Any?], hits: String?) -> String {
        var key = w
        for v in a { key += "\u{1}"; if let v { key += "\(v)" } else { key += "\u{2}" } }
        if w.contains("temp.hits") { key += "\u{3}" + (hits ?? "") }
        return key
    }

    /// Počet produktů pro filtr. Mezi staženími dat se nemění, takže se při stránkování nepočítá znovu
    /// (výjimkou jsou filtry závislé na datech uživatele, ty se počítají vždy).
    private func total(_ w: String, _ a: [Any?]) throws -> Int {
        let db = try data()
        if w.contains("u.") { return (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0 }
        let key = Self.cacheKey(w, a, hits: hitsKey)
        if let hit = countCache[key] { return hit }
        let n = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
        if countCache.count > 300 { countCache.removeAll() }
        countCache[key] = n
        return n
    }

    private func computeResolve(raw: String, tokens: [String]) throws -> Resolved {
        if try count(tokens) > 0 { return Resolved(tokens: tokens) }   // běžný případ: bez překlepu
        let db = try data()
        let speller = try loadSpeller(db)
        var fixed = tokens
        var shown = Self.tokenize(display: raw)
        var changed = false
        for (i, tok) in tokens.enumerated() {
            if tok.count < 4 || tok.allSatisfy(\.isNumber) { continue }
            if try count([tok]) > 0 { continue }                          // slovo existuje
            guard let m = speller.correct(tok) else { continue }
            fixed[i] = m.word
            if i < shown.count { shown[i] = m.display }
            changed = true
        }
        let corrected = changed ? shown.joined(separator: " ") : nil
        if try count(fixed) > 0 { return Resolved(tokens: fixed, corrected: corrected) }
        if fixed.count > 1, try count(fixed, any: true) > 0 { return Resolved(tokens: fixed, corrected: corrected, any: true) }
        return Resolved(tokens: fixed, corrected: corrected)
    }

    private static func tokenize(display s: String) -> [String] {
        s.lowercased().components(separatedBy: tokenChars).filter { !$0.isEmpty }
    }

    // MARK: - hledání + fasety

    private func search(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        let page = max(1, Int(q["page"] ?? "1") ?? 1)
        let order = Self.sorts[q["sort"] ?? "relevance"] ?? Self.sorts["relevance"]!
        let store = (q["store"].flatMap { $0.isEmpty ? nil : $0 }) ?? setting("store")
        let (w, a) = try buildWhere(q)
        let total = try total(w, a)
        let r = resolve(q)
        var orderSQL = order, orderArgs: [Any?] = []
        if r.any, (q["sort"] ?? "relevance") == "relevance" {
            if caps.psearch {
                // počet nalezených slov je už spočítaný v pomocné tabulce
                orderSQL = "(SELECT h.n FROM temp.hits h WHERE h.id = p.rowid) DESC, " + order
            } else {
                orderSQL = "(" + r.tokens.map { _ in "(p.search LIKE ?)" }.joined(separator: " + ") + ") DESC, " + order
                orderArgs = r.tokens.map { "%\($0)%" }
            }
        }
        let rows = try db.query("SELECT \(itemCols) FROM products p WHERE \(w) ORDER BY \(orderSQL) LIMIT ? OFFSET ?",
                                a + orderArgs + [Self.pageSize, (page - 1) * Self.pageSize])
        var out: [String: Any] = ["total": total, "page": page, "pages": (total + Self.pageSize - 1) / Self.pageSize,
                                  "items": try itemsFor(rows, store: store)]
        if let c = r.corrected { out["corrected"] = c }
        if r.any { out["partial"] = true }
        if q["facets"] != "0" { out["facets"] = try facets(q) }
        return out
    }

    private func facets(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        var f: [String: Any] = [:]
        let level = q["cat2"] != nil ? "cat3" : q["cat1"] != nil ? "cat2" : "cat1"
        var (w, a) = try buildWhere(q)
        // Filtry pro stejný dotaz se mezi staženími dat nemění (kromě těch závislých na hlídaných produktech).
        let cacheKey = Self.cacheKey(w, a, hits: hitsKey) + "\u{4}" + q.keys.filter { $0.hasPrefix("a_") || ["brand", "pmin", "pmax", "label", "cat1", "cat2", "cat3"].contains($0) }
            .sorted().map { "\($0)=\(q[$0] ?? "")" }.joined(separator: "\u{5}")
        let cacheable = !w.contains("u.")
        if cacheable, let hit = facetsCache[cacheKey] { return hit }
        f["categories"] = ["level": level, "values": try db.query(
            "SELECT p.\(level) AS value, COUNT(*) AS count FROM products p WHERE \(w) AND p.\(level) IS NOT NULL GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 60", a)]
        (w, a) = try buildWhere(q, skip: ["brand"])
        f["brands"] = try db.query(
            "SELECT p.brand AS value, COUNT(*) AS count FROM products p WHERE \(w) AND p.brand IS NOT NULL GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 300", a)
        (w, a) = try buildWhere(q, skip: ["price"])
        let pr = try db.query("SELECT MIN(p.price) AS min, MAX(p.price) AS max FROM products p WHERE \(w)", a).first ?? [:]
        f["price"] = ["min": pr["min"] ?? NSNull(), "max": pr["max"] ?? NSNull()]
        (w, a) = try buildWhere(q, skip: ["label"])
        // Štítky: produkty se seskupí podle (pár set různých) kombinací štítků a spočítá se z nich,
        // místo devíti porovnání LIKE u každého produktu.
        let combos = try db.query("SELECT p.labels AS labels, COUNT(*) AS c FROM products p WHERE \(w) GROUP BY p.labels", a)
        var labels: [[String: Any]] = []
        for key in Self.labelOrder {
            let needle = ",\(key),"
            var c = 0
            for g in combos {
                if let l = g["labels"] as? String, l.range(of: needle, options: .caseInsensitive) != nil { c += g["c"] as? Int ?? 0 }
            }
            if c > 0 { labels.append(["value": key, "label": Self.labels[key]!, "count": c]) }
        }
        f["labels"] = labels
        var attrs: [[String: Any]] = []
        if q["cat2"] != nil || q["cat3"] != nil {
            (w, a) = try buildWhere(q)
            let total = max(1, try self.total(w, a))
            // nejdřív se spočítají hodnoty (podle čísla hodnoty), teprve pak se k nim dohledá název
            let rows = try db.query("""
                SELECT av.code AS code, av.value AS value, g.c AS c FROM (
                    SELECT pa.vid AS vid, COUNT(*) AS c FROM products p JOIN product_attrs pa ON pa.sku = p.sku
                    WHERE \(w) GROUP BY pa.vid) g
                JOIN attr_values av ON av.id = g.vid ORDER BY g.vid
                """, a)
            var groups: [String: [(String, Int)]] = [:]
            for r in rows {
                guard let code = r["code"] as? String, let value = r["value"] as? String else { continue }
                groups[code, default: []].append((value, r["c"] as? Int ?? 0))
            }
            var labelOf: [String: String] = attrLabels ?? [:]
            if attrLabels == nil {
                for r in try db.query("SELECT code, label FROM attrs") {
                    if let c = r["code"] as? String { labelOf[c] = r["label"] as? String ?? c }
                }
                attrLabels = labelOf
            }
            var cands: [(sel: Bool, cov: Double, code: String, vals: [(String, Int)])] = []
            for (code, vals) in groups {
                guard labelOf[code] != nil, vals.count >= 2 else { continue }
                let cov = Double(vals.reduce(0) { $0 + $1.1 }) / Double(total)
                let sel = !many(q, "a_" + code).isEmpty
                if cov >= 0.25 || sel { cands.append((sel, cov, code, vals)) }
            }
            cands.sort { ($0.sel ? 0 : 1, -$0.cov) < ($1.sel ? 0 : 1, -$1.cov) }
            for c in cands.prefix(10) {
                // klíč pro řazení se spočítá pro každou hodnotu jednou, ne při každém porovnání
                let keyed = c.vals.map { (key: Self.numericKey($0.0), value: $0.0, count: $0.1) }
                let sorted = keyed.sorted { $0.key < $1.key }
                attrs.append(["code": c.code, "label": labelOf[c.code]!,
                              "values": sorted.prefix(60).map { ["value": $0.value, "count": $0.count] }])
            }
        }
        f["attrs"] = attrs
        if cacheable {
            if facetsCache.count > 60 { facetsCache.removeAll() }
            facetsCache[cacheKey] = f
        }
        return f
    }

    /// Řazení hodnot parametrů: čísla podle velikosti ("12 V" < "18 V"), pak text.
    private static func numericKey(_ v: String) -> NumericKey {
        let scanner = Scanner(string: v.replacingOccurrences(of: ",", with: "."))
        scanner.charactersToBeSkipped = .whitespaces
        if let d = scanner.scanDouble() { return NumericKey(isText: false, number: d, text: v) }
        return NumericKey(isText: true, number: 0, text: v)
    }

    struct NumericKey: Comparable {
        let isText: Bool
        let number: Double
        let text: String
        static func < (l: NumericKey, r: NumericKey) -> Bool {
            if l.isText != r.isText { return !l.isText }
            if l.number != r.number { return l.number < r.number }
            return l.text.localizedStandardCompare(r.text) == .orderedAscending
        }
    }

    // MARK: - kategorie, našeptávač

    /// Kategorie dané úrovně seřazené podle počtu produktů. U každé: fotky nejlépe
    /// hodnocených produktů (místo náhodné), tři největší podkategorie a kolik je v ní slev.
    private func categories(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        let c1 = q["cat1"], c2 = q["cat2"]
        // kategorie se mezi staženími dat nemění
        let cacheKey = (c1 ?? "") + "\u{1}" + (c2 ?? "") + "\u{1}" + (c1 == nil ? "0" : c2 == nil ? "1" : "2")
        if let hit = categoriesCache[cacheKey] { return hit }
        var level = "cat1", filter = "1 = 1"
        var child: String? = "cat2"
        var args: [Any?] = []
        if let c1, let c2 {
            level = "cat3"; child = nil; filter = "cat1 = ? AND cat2 = ?"; args = [c1, c2]
        } else if let c1 {
            level = "cat2"; child = "cat3"; filter = "cat1 = ?"; args = [c1]
        }
        let base = "price IS NOT NULL AND \(filter) AND \(level) IS NOT NULL"
        var values = try db.query("SELECT \(level) AS value, COUNT(*) AS count FROM products WHERE \(base) GROUP BY 1 ORDER BY 2 DESC", args)
        var images: [String: [String]] = [:]
        if level == "cat1" {
            // první úroveň: tři nejlépe hodnocené produkty každého oddělení přímo z indexu (cat1, rank, sku),
            // místo očíslování všech produktů okenní funkcí
            for row in values {
                guard let v = row["value"] as? String else { continue }
                for r in try db.query("SELECT image FROM products WHERE price IS NOT NULL AND cat1 = ? AND image IS NOT NULL ORDER BY rank DESC, sku LIMIT 3", [v]) {
                    if let img = r["image"] as? String { images[v, default: []].append(img) }
                }
            }
        } else {
            for r in try db.query("""
                SELECT value, image FROM (SELECT \(level) AS value, image,
                  ROW_NUMBER() OVER (PARTITION BY \(level) ORDER BY rank DESC, sku) AS rn
                  FROM products WHERE \(base) AND image IS NOT NULL) WHERE rn <= 3
                """, args) {
                if let v = r["value"] as? String, let img = r["image"] as? String { images[v, default: []].append(img) }
            }
        }
        var subs: [String: [String]] = [:]
        if let child {
            for r in try db.query("SELECT \(level) AS value, \(child) AS sub, COUNT(*) AS n FROM products WHERE \(base) AND \(child) IS NOT NULL GROUP BY 1, 2 ORDER BY 3 DESC", args) {
                if let v = r["value"] as? String, let sub = r["sub"] as? String, (subs[v]?.count ?? 0) < 3 { subs[v, default: []].append(sub) }
            }
        }
        for k in values.indices {
            guard let v = values[k]["value"] as? String else { continue }
            values[k]["image"] = images[v]?.first ?? NSNull()
            values[k]["images"] = images[v] ?? []
            values[k]["subs"] = subs[v] ?? []
        }
        let total = try db.scalar("SELECT COUNT(*) FROM products WHERE price IS NOT NULL AND \(filter)", args) as? Int ?? 0
        let discounted = try db.scalar("SELECT COUNT(*) FROM products WHERE price IS NOT NULL AND COALESCE(real_discount, 0) > 0 AND \(filter)", args) as? Int ?? 0
        let out: [String: Any] = ["level": level, "values": values, "total": total, "discounted": discounted]
        if categoriesCache.count > 200 { categoriesCache.removeAll() }
        categoriesCache[cacheKey] = out
        return out
    }

    private struct SuggestIndex {
        struct Category { let row: [String: Any]; let folded: String }
        let categories: [Category]
        let brands: [(name: String, folded: String)]
    }

    /// Kategorie a značky se při psaní neprochází v databázi znovu a znovu – načtou se jednou po otevření dat.
    private func loadSuggestIndex(_ db: SQLiteDB) throws -> SuggestIndex {
        if let suggestIndex { return suggestIndex }
        var cats: [SuggestIndex.Category] = []
        for lvl in ["cat3", "cat2"] {
            let group = lvl == "cat3" ? "cat1, cat2, cat3" : "cat1, cat2"
            for r in try db.query("SELECT cat1, cat2, \(lvl == "cat3" ? "cat3" : "NULL AS cat3"), COUNT(*) AS count FROM products WHERE \(lvl) IS NOT NULL GROUP BY \(group) ORDER BY \(group)") {
                guard let name = r[lvl] as? String else { continue }
                cats.append(.init(row: ["cat1": r["cat1"] ?? NSNull(), "cat2": r["cat2"] ?? NSNull(), "cat3": r["cat3"] ?? NSNull(),
                                        "name": name, "count": r["count"] ?? 0], folded: Self.fold(name)))
            }
        }
        let brands = try db.query("SELECT DISTINCT brand FROM products WHERE brand IS NOT NULL ORDER BY brand")
            .compactMap { $0["brand"] as? String }.map { ($0, Self.fold($0)) }
        let index = SuggestIndex(categories: cats, brands: brands)
        suggestIndex = index
        return index
    }

    private func suggest(_ text: String) throws -> [String: Any] {
        let db = try data()
        let t = Self.fold(text).trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return ["products": [], "categories": [], "brands": []] }
        var products: [[String: Any]]
        let fromHits = "SELECT sku, name, price, image FROM products p WHERE price IS NOT NULL AND \(Self.hitsClause) ORDER BY rank DESC, p.rowid LIMIT 6"
        if caps.psearch {
            // celý napsaný text jako jedna fráze (stejně jako dřív LIKE '%text%')
            let index = try loadSearchIndex()
            try fillHits(key: "p" + t, rows: try rows(matching: t, in: index), counts: nil)
            products = try db.query(fromHits)
        } else {
            products = try db.query("SELECT sku, name, price, image FROM products WHERE price IS NOT NULL AND search LIKE ? ORDER BY rank DESC LIMIT 6", ["%\(t)%"])
        }
        var corrected: String?
        if products.isEmpty {
            let r = resolve(["q": text])
            if let c = r.corrected, !r.tokens.isEmpty {
                corrected = c
                if caps.psearch {
                    try ensureHits(tokens: r.tokens, any: r.any)
                    products = try db.query(fromHits)
                } else {
                    let w = r.tokens.map { _ in "search LIKE ?" }.joined(separator: r.any ? " OR " : " AND ")
                    products = try db.query("SELECT sku, name, price, image FROM products WHERE price IS NOT NULL AND (\(w)) ORDER BY rank DESC LIMIT 6",
                                            r.tokens.map { "%\($0)%" })
                }
            }
        }
        let index = try loadSuggestIndex(db)
        let cats = index.categories.lazy.filter { $0.folded.contains(t) }.prefix(5).map(\.row)
        let brands = index.brands.lazy.filter { $0.folded.contains(t) }.prefix(4).map(\.name)
        var out: [String: Any] = ["products": products, "categories": Array(cats), "brands": Array(brands)]
        if let corrected { out["corrected"] = corrected }
        return out
    }

    // MARK: - úvod, detail, hlídané

    private func home() throws -> [String: Any] {
        let db = try data()
        let store = setting("store") ?? "888"
        let sname = (try db.scalar("SELECT name FROM stores WHERE code = ?", [store]) as? String) ?? store
        var sections: [[String: Any]] = []
        // vychází se z (malé) tabulky hlídaných, ne z procházení všech produktů
        let watched = try db.query("""
            SELECT \(itemCols) FROM u.watch w CROSS JOIN products p ON p.sku = w.sku
            WHERE p.price IS NOT NULL AND p.price < w.added_price ORDER BY p.drop_pct DESC, p.rowid LIMIT 12
            """)
        if !watched.isEmpty {
            sections.append(["title": "Hlídané, které zlevnily", "query": ["watch": "1"], "items": try itemsFor(watched, store: store)])
        }
        // Sekce určuje soubor ponk/home_sections.json na GitHubu – nové jdou přidat bez aktualizace aplikace.
        var defs: [[String: Any]] = []
        if let json = info("home_sections_v2") ?? info("home_sections"), let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] {
            defs = parsed
        } else {
            defs = [["title": "Zlevněno při poslední kontrole", "query": ["drop_days": "1", "sort": "drop"]],
                    ["title": "Výprodej skladem: {store_name}", "query": ["label": "sell_off", "store": "{store}", "sort": "discount"]],
                    ["title": "Největší skutečné slevy", "query": ["disc": "30", "sort": "discount"]]]
        }
        for def in defs {
            guard let title = def["title"] as? String, let raw = def["query"] as? [String: Any] else { continue }
            var q: [String: String] = [:]
            for (k, v) in raw {
                q[k] = "\(v)".replacingOccurrences(of: "{store}", with: store).replacingOccurrences(of: "{store_name}", with: sname)
            }
            if q["restock_days"] != nil, !caps.restock { continue }
            let (w, a) = try buildWhere(q)
            let order = Self.sorts[q["sort"] ?? "relevance"] ?? Self.sorts["relevance"]!
            let rows = try db.query("SELECT \(itemCols) FROM products p WHERE \(w) ORDER BY \(order) LIMIT 12", a)
            if !rows.isEmpty {
                sections.append(["title": title.replacingOccurrences(of: "{store_name}", with: sname), "query": q,
                                 "items": try itemsFor(rows, store: store)])
            }
        }
        return ["sections": sections, "watched_drops": 0]
    }

    // MARK: - mapa prodejny

    private func storeMap(_ store: String) throws -> [String: Any]? {
        let db = try data()
        guard caps.maps, let m = try db.query("SELECT image, width, height FROM store_maps WHERE store = ?", [store]).first else { return nil }
        let labels = try db.query("SELECT lo, hi, x, y, w, h, zx, zy, zw, zh FROM store_map_labels WHERE store = ? ORDER BY lo", [store])
        return ["store": store, "image": m["image"] ?? "", "width": m["width"] ?? 0, "height": m["height"] ?? 0, "labels": labels]
    }

    private func product(_ sku: String) throws -> [String: Any]? {
        let db = try data()
        guard var p = try db.query("SELECT * FROM products WHERE sku = ?", [sku]).first else { return nil }
        p["search"] = nil
        p["cat_path"] = ["cat1", "cat2", "cat3"].compactMap { p[$0] as? String }
        p["gallery"] = (p["image"] as? String).map { [$0] } ?? []
        p["usps"] = [String]()
        p["positions"] = [String: Any]()
        p["description"] = NSNull()
        p["labels"] = ((p["labels"] as? String) ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        p["history"] = try db.query("SELECT day, price FROM price_history WHERE sku = ? ORDER BY day", [sku])
        var stock: [String: Any] = [:]
        for r in try db.query("SELECT store, qty FROM stock WHERE sku = ?", [sku]) {
            if let s = r["store"] as? String { stock[s] = r["qty"] }
        }
        p["stock"] = stock
        p["params"] = try db.query("""
            SELECT a.label AS label, GROUP_CONCAT(av.value, ', ') AS value FROM product_attrs pa
            JOIN attr_values av ON av.id = pa.vid JOIN attrs a ON a.code = av.code
            WHERE pa.sku = ? GROUP BY av.code ORDER BY a.label
            """, [sku])
        if let w = try db.query("SELECT sku, added, added_price, target FROM u.watch WHERE sku = ?", [sku]).first { p["watch"] = w }
        if caps.extras { try addExtras(&p, sku: sku, db: db) }
        if caps.platforms { try addPlatform(&p, sku: sku, db: db) }
        p["purchases"] = (try? db.query("SELECT day, kind, ref, qty FROM u.purchases WHERE sku = ? ORDER BY day DESC LIMIT 5", [sku])) ?? []
        return p
    }

    /// Seznam platforem z dat (JSON se rozebere jednou, ne u každého detailu produktu).
    private func platformList0() throws -> [[String: Any]]? {
        if let platformDefs { return platformDefs }
        guard let raw = info("platforms"),
              let list = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else { return nil }
        platformDefs = list
        return list
    }

    /// Platformy s počtem produktů (pro výběr „moje aku platformy“).
    private func platformList() throws -> [[String: Any]] {
        guard caps.platforms, let list = try platformList0() else { return [] }
        var counts: [String: Int] = [:]
        for r in try data().query("""
            SELECT x.platform AS platform, COUNT(*) AS n FROM platforms x JOIN products p ON p.sku = x.sku
            WHERE p.price IS NOT NULL GROUP BY x.platform
            """) {
            if let id = r["platform"] as? String { counts[id] = r["n"] as? Int ?? 0 }
        }
        return list.compactMap { e in
            guard let id = e["id"] as? String, let n = counts[id], n > 0 else { return nil }
            return ["id": id, "title": e["title"] as? String ?? id, "count": n]
        }
    }

    /// Platforma produktu a k tělu sady s akumulátorem (nebo k sadě samotné tělo).
    private func addPlatform(_ p: inout [String: Any], sku: String, db: SQLiteDB) throws {
        guard let x = try db.query("SELECT platform, kind, body, model FROM platforms WHERE sku = ?", [sku]).first,
              let id = x["platform"] as? String else { return }
        var title = id
        if let list = try platformList0(),
           let e = list.first(where: { $0["id"] as? String == id }) { title = e["title"] as? String ?? id }
        let body = x["body"] as? Int
        p["platform"] = ["id": id, "title": title, "kind": x["kind"] ?? NSNull(), "body": body ?? NSNull()] as [String: Any]
        guard let body, let model = x["model"] as? String else { return }
        let rows = try db.query("""
            SELECT \(itemCols) FROM products p JOIN platforms x ON x.sku = p.sku
            WHERE x.platform = ? AND x.model = ? AND x.body = ? AND p.sku <> ? AND p.price IS NOT NULL
            ORDER BY p.price LIMIT 6
            """, [id, model, 1 - body, sku])
        p["platform_alt"] = try itemsFor(rows, store: setting("store"))
    }

    /// Akce výrobců (dárky, cashback…), obsah balení, dokumenty, výrobce, bezpečnost,
    /// množstevní ceny a související produkty – připravuje denní úloha na GitHubu.
    private func addExtras(_ p: inout [String: Any], sku: String, db: SQLiteDB) throws {
        guard let raw = try db.scalar("SELECT data FROM extras WHERE sku = ?", [sku]) as? String,
              let e = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return }
        let today = Self.today()
        if let ids = e["banners"] as? [Int], !ids.isEmpty {
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            p["promos"] = try db.query("""
                SELECT id, label, text, link, image, background, kind, gift, start, "end", store_only, value FROM banners
                WHERE id IN (\(marks)) AND ("end" IS NULL OR "end" >= ?) AND (start IS NULL OR start <= ?)
                ORDER BY CASE kind WHEN 'gift' THEN 0 WHEN 'deal' THEN 1 WHEN 'cashback' THEN 2 WHEN 'contest' THEN 3 ELSE 4 END
                """, ids + [today, today])
        }
        for key in ["box", "warranty", "energy", "documents", "producer", "safety", "tiers"] {
            if let v = e[key] { p[key] = v }
        }
        p["exclusive"] = (e["exclusive"] as? Int ?? 0) == 1
        p["assembly"] = (e["assembly"] as? Int ?? 0) == 1
        p["rental"] = (e["rental"] as? Int ?? 0) == 1
        let links = e["links"] as? [String: [String]] ?? [:]
        func items(_ skus: [String]) throws -> [[String: Any]] {
            try itemsBySKU(skus.filter { $0 != sku }).filter { $0["price"] is Double }
        }
        p["related"] = try items((links["related"] ?? []) + (links["crosssell"] ?? []))
        p["alternatives"] = try items(links["upsell"] ?? [])
        p["series"] = try items(e["series"] as? [String] ?? [])
    }

    /// Produkty podle naskenovaného čárového kódu. EAN-13 i UPC (12 číslic, čtečka k nim
    /// přidá nulu na začátek), případně kód produktu Bauhausu.
    private func itemsByEAN(_ code: String) throws -> [[String: Any]] {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 5 else { return [] }
        let trimmed = String(digits.drop { $0 == "0" })
        let rows = try data().query(
            "SELECT sku FROM products WHERE ean = ? OR sku = ? OR (length(ean) BETWEEN 5 AND 13 AND ltrim(ean, '0') = ?) "
            + "ORDER BY active DESC LIMIT 5", [digits, digits, trimmed])
        return try itemsBySKU(rows.compactMap { $0["sku"] as? String })
    }

    /// Produkty podle kódů ve stejném pořadí (naposledy prohlížené).
    private func itemsBySKU(_ skus: [String]) throws -> [[String: Any]] {
        guard !skus.isEmpty else { return [] }
        let list = Array(skus.prefix(50))
        let rows = try data().query("SELECT \(itemCols) FROM products p WHERE p.sku IN (\(Array(repeating: "?", count: list.count).joined(separator: ",")))", list)
        let order = Dictionary(list.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = rows.sorted { (order[$0["sku"] as? String ?? ""] ?? 0) < (order[$1["sku"] as? String ?? ""] ?? 0) }
        return try itemsFor(sorted, store: setting("store"))
    }

    private func watchItems() throws -> [[String: Any]] {
        guard let db else { return [] }
        let rows = try db.query("""
            SELECT \(itemCols), w.added, w.added_price, w.target FROM u.watch w
            CROSS JOIN products p ON p.sku = w.sku ORDER BY (p.price < w.added_price) DESC, w.added DESC, p.rowid
            """)
        return try itemsFor(rows, store: setting("store"))
    }

    /// Data pro widget „Můj Bauhaus“ (WidgetSnapshot): hlídané, aktuální seznam, novinky skladem.
    private func widgetSnapshot(listID: Int?) throws -> [String: Any] {
        let user = try userDB()
        let store = setting("store") ?? "888"
        var out: [String: Any] = ["storeName": store, "watchTotal": 0, "watchDropped": 0, "restockCount": 0, "restock": []]
        func product(_ r: [String: Any], drop: Double? = nil) -> [String: Any] {
            var p: [String: Any] = ["sku": r["sku"] ?? "", "name": r["name"] ?? ""]
            if let v = num(r["price"]) { p["price"] = v }
            if let v = r["image"] as? String { p["image"] = v }
            if let drop { p["drop"] = drop }
            return p
        }
        if let db {
            if let name = try db.scalar("SELECT name FROM stores WHERE code = ?", [store]) as? String { out["storeName"] = name }
            // hlídané: kolik zlevnilo od přidání a které nejvíc (v Kč)
            let watched = try db.query("""
                SELECT p.sku, p.name, p.price, p.image, w.added_price FROM u.watch w
                CROSS JOIN products p ON p.sku = w.sku ORDER BY w.added DESC, p.rowid
                """)
            out["watchTotal"] = watched.count
            var dropped = 0
            var top: ([String: Any], Double)?
            for r in watched {
                guard let price = num(r["price"]), let added = num(r["added_price"]), price < added else { continue }
                dropped += 1
                if top == nil || added - price > top!.1 { top = (r, added - price) }
            }
            out["watchDropped"] = dropped
            if let top { out["watchTop"] = product(top.0, drop: top.1) } else if let first = watched.first { out["watchTop"] = product(first) }
            // novinky skladem ve zvolené prodejně (poslední den, kdy nějaké byly)
            if caps.restock, let day = try db.scalar("SELECT MAX(day) FROM restock WHERE store = ?", [store]) as? String {
                out["restockDay"] = day
                out["restockCount"] = (try db.scalar("""
                    SELECT COUNT(*) FROM restock r JOIN products p ON p.sku = r.sku
                    WHERE r.store = ? AND r.day = ? AND p.price IS NOT NULL
                    """, [store, day]) as? Int) ?? 0
                out["restock"] = try db.query("""
                    SELECT p.sku, p.name, p.price, p.image FROM restock r JOIN products p ON p.sku = r.sku
                    WHERE r.store = ? AND r.day = ? AND p.price IS NOT NULL
                    ORDER BY (p.image IS NULL), p.rank DESC, p.sku LIMIT 3
                    """, [store, day]).map { product($0) }
            }
        }
        // nákupní seznam otevřený v aplikaci (jinak první)
        let lists = try user.query("SELECT id, name FROM \(t("lists")) ORDER BY id")
        if let l = lists.first(where: { ($0["id"] as? Int) == listID }) ?? lists.first, let id = l["id"] as? Int {
            let items = try user.query("SELECT sku, qty, checked FROM \(t("list_items")) WHERE list_id = ?", [id])
            var prices: [String: Double] = [:]
            let skus = items.compactMap { $0["sku"] as? String }
            if let db, !skus.isEmpty {
                let marks = Array(repeating: "?", count: skus.count).joined(separator: ",")
                for r in try db.query("SELECT sku, price FROM products WHERE sku IN (\(marks))", skus) {
                    if let s = r["sku"] as? String, let v = num(r["price"]) { prices[s] = v }
                }
            }
            var sum = 0.0
            for i in items {
                if let sku = i["sku"] as? String, let v = prices[sku] { sum += v * (num(i["qty"]) ?? 1) }
            }
            out["list"] = ["id": id, "name": l["name"] as? String ?? "Nákupní seznam",
                           "done": items.filter { ($0["checked"] as? Int ?? 0) != 0 }.count,
                           "total": items.count, "sum": sum]
        }
        return out
    }

    private func savedItems() throws -> [[String: Any]] {
        let user = try userDB()
        var out: [[String: Any]] = []
        for r in try user.query("SELECT * FROM \(t("saved")) ORDER BY id DESC") {
            let q = (try? JSONSerialization.jsonObject(with: Data(((r["query"] as? String) ?? "{}").utf8))) as? [String: Any] ?? [:]
            let query = q.mapValues { "\($0)" }
            var fresh = 0, total = 0
            if let db {
                var withSince = query
                withSince["since"] = r["checked"] as? String ?? Self.today()
                var (w, a) = try buildWhere(withSince)
                fresh = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
                (w, a) = try buildWhere(query)
                total = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
            }
            out.append(["id": r["id"] ?? 0, "name": r["name"] ?? "", "query": query, "fresh": fresh, "total": total])
        }
        return out
    }

    // MARK: - nákupní seznamy

    private func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private func shoppingList(method: String, parts: [String], query: [String: String], body: [String: Any]?) throws -> Any {
        let user = try userDB()
        let L = t("lists"), I = t("list_items")
        let id = parts.count > 1 ? Int(parts[1]) : nil
        switch (method, parts[0]) {
        case ("GET", "lists"):
            let rows = try user.query("""
                SELECT l.id, l.name, l.store, l.share_id, COUNT(i.id) AS count, COALESCE(SUM(i.checked = 0), 0) AS open
                FROM \(L) l LEFT JOIN \(I) i ON i.list_id = l.id GROUP BY l.id ORDER BY l.id
                """)
            return ["items": rows]
        case ("POST", "lists"):
            let name = (body?["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if let id {
                if !name.isEmpty { try user.run("UPDATE \(L) SET name = ? WHERE id = ?", [name, id]) }
                if let store = body?["store"] as? String { try user.run("UPDATE \(L) SET store = ? WHERE id = ?", [store.isEmpty ? nil : store, id]) }
                return ["ok": true, "id": id]
            }
            try user.run("INSERT INTO \(L)(name, created) VALUES(?, ?)", [name.isEmpty ? "Nový seznam" : name, Self.today()])
            return ["ok": true, "id": try user.scalar("SELECT MAX(id) FROM \(L)") ?? 0]
        case ("DELETE", "lists"):
            guard let id else { throw EngineError.notFound }
            try user.run("DELETE FROM \(I) WHERE list_id = ?", [id])
            try user.run("DELETE FROM \(L) WHERE id = ?", [id])
            try user.run("INSERT INTO \(L)(name, created) SELECT 'Nákupní seznam', ? WHERE NOT EXISTS (SELECT 1 FROM \(L))", [Self.today()])
            return ["ok": true]
        case ("GET", "listshare"):
            // seznam ke sdílení odkazem; sdílený seznam má trvalé id, aby se u druhého slučoval
            guard let id, let list = try user.query("SELECT id, name, store, share_id FROM \(L) WHERE id = ?", [id]).first else {
                throw EngineError.notFound
            }
            var sid = list["share_id"] as? String ?? ""
            if sid.isEmpty {
                sid = UUID().uuidString
                try user.run("UPDATE \(L) SET share_id = ? WHERE id = ?", [sid, id])
            }
            let items = try user.query("SELECT sku, text, qty, checked FROM \(I) WHERE list_id = ? ORDER BY id", [id])
            return ["sid": sid, "name": list["name"] ?? "Seznam", "store": list["store"] ?? NSNull(), "items": items]
        case ("POST", "listshare"):
            // načtení sdíleného seznamu: sloučí se se stejným seznamem (podle id), jinak vznikne nový;
            // nic se nemaže, odškrtnuté zůstane odškrtnuté a množství se vezme větší
            let sid = body?["sid"] as? String ?? UUID().uuidString
            let name = (body?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Sdílený seznam"
            var listID = try user.scalar("SELECT id FROM \(L) WHERE share_id = ?", [sid]) as? Int
            let isNew = listID == nil
            if listID == nil {
                try user.run("INSERT INTO \(L)(name, created, store, share_id) VALUES(?, ?, ?, ?)",
                             [name, Self.today(), body?["store"] as? String, sid])
                listID = try user.scalar("SELECT MAX(id) FROM \(L)") as? Int
            }
            guard let lid = listID else { throw EngineError.notFound }
            var added = 0, updated = 0
            for item in body?["items"] as? [[String: Any]] ?? [] {
                let sku = (item["sku"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let text = (item["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard sku != nil || text != nil else { continue }
                let qty = num(item["qty"]) ?? 1
                let checked = (item["checked"] as? Int ?? 0) != 0 || (item["checked"] as? Bool ?? false)
                let existing: [String: Any]?
                if let sku {
                    existing = try user.query("SELECT id, qty, checked FROM \(I) WHERE list_id = ? AND sku = ? LIMIT 1", [lid, sku]).first
                } else {
                    existing = try user.query("SELECT id, qty, checked FROM \(I) WHERE list_id = ? AND sku IS NULL AND text = ? LIMIT 1", [lid, text]).first
                }
                if let e = existing, let eid = e["id"] as? Int {
                    let q = max(num(e["qty"]) ?? 1, qty)
                    let c = ((e["checked"] as? Int ?? 0) != 0) || checked
                    if q != (num(e["qty"]) ?? 1) || c != ((e["checked"] as? Int ?? 0) != 0) { updated += 1 }
                    try user.run("UPDATE \(I) SET qty = ?, checked = ? WHERE id = ?", [q, c ? 1 : 0, eid])
                } else {
                    var price: Any? = nil
                    if let sku, let db { price = try db.scalar("SELECT price FROM products WHERE sku = ?", [sku]) }
                    try user.run("INSERT INTO \(I)(list_id, sku, text, qty, checked, added, added_price) VALUES(?, ?, ?, ?, ?, ?, ?)",
                                 [lid, sku, text, qty, checked ? 1 : 0, Self.today(), price])
                    added += 1
                }
            }
            return ["id": lid, "name": name, "added": added, "updated": updated, "new": isNew]
        case ("GET", "inlists"):
            let rows = try user.query("""
                SELECT l.id AS list_id, l.name, i.qty, i.checked FROM \(I) i JOIN \(L) l ON l.id = i.list_id WHERE i.sku = ?
                """, [query["sku"] ?? ""])
            return ["items": rows]
        case ("GET", "list"):
            guard let id, let list = try user.query("SELECT id, name, store FROM \(L) WHERE id = ?", [id]).first else {
                throw EngineError.notFound
            }
            return try listDetail(list)
        case ("POST", "list"):
            // přidat položku: produkt (sku) nebo vlastní text; stejný produkt jen navýší množství
            guard let id else { throw EngineError.notFound }
            let qty = num(body?["qty"]) ?? 1
            if let sku = body?["sku"] as? String, !sku.isEmpty {
                if let existing = try user.scalar("SELECT id FROM \(I) WHERE list_id = ? AND sku = ? AND checked = 0", [id, sku]) as? Int {
                    try user.run("UPDATE \(I) SET qty = qty + ? WHERE id = ?", [qty, existing])
                } else {
                    let price = db != nil ? try db!.scalar("SELECT price FROM products WHERE sku = ?", [sku]) : nil
                    try user.run("INSERT INTO \(I)(list_id, sku, qty, added, added_price) VALUES(?, ?, ?, ?, ?)",
                                 [id, sku, qty, Self.today(), price])
                }
            } else if let text = (body?["text"] as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                try user.run("INSERT INTO \(I)(list_id, text, qty, added) VALUES(?, ?, ?, ?)", [id, text, qty, Self.today()])
            }
            if let mode = body?["clear"] as? String {
                switch mode {
                case "checked": try user.run("DELETE FROM \(I) WHERE list_id = ? AND checked = 1", [id])
                case "uncheck": try user.run("UPDATE \(I) SET checked = 0 WHERE list_id = ?", [id])
                case "all": try user.run("DELETE FROM \(I) WHERE list_id = ?", [id])
                default: break
                }
            }
            return ["ok": true]
        case ("POST", "listitem"):
            guard let id else { throw EngineError.notFound }
            if let q = num(body?["qty"]) {
                if q <= 0 { try user.run("DELETE FROM \(I) WHERE id = ?", [id]) } else { try user.run("UPDATE \(I) SET qty = ? WHERE id = ?", [q, id]) }
            }
            if let c = body?["checked"] as? Bool { try user.run("UPDATE \(I) SET checked = ? WHERE id = ?", [c ? 1 : 0, id]) }
            if let n = body?["note"] as? String { try user.run("UPDATE \(I) SET note = ? WHERE id = ?", [n.isEmpty ? nil : n, id]) }
            if let txt = body?["text"] as? String, !txt.isEmpty { try user.run("UPDATE \(I) SET text = ? WHERE id = ?", [txt, id]) }
            return ["ok": true]
        case ("DELETE", "listitem"):
            guard let id else { throw EngineError.notFound }
            try user.run("DELETE FROM \(I) WHERE id = ?", [id])
            return ["ok": true]
        default:
            throw EngineError.notFound
        }
    }

    /// Položky seznamu s cenou a skladem + kolik položek mají jednotlivé prodejny skladem.
    private func listDetail(_ list: [String: Any]) throws -> [String: Any] {
        let user = try userDB()
        let listID = list["id"] as? Int ?? 0
        let store = (list["store"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? setting("store") ?? "888"
        var rows = try user.query("SELECT id, sku, text, qty, checked, note, added, added_price FROM \(t("list_items")) WHERE list_id = ? ORDER BY id",
                                  [listID])
        let skus = rows.compactMap { $0["sku"] as? String }
        var product: [String: [String: Any]] = [:]
        var stock: [String: [String: Double]] = [:]   // sku → prodejna → ks
        if let db, !skus.isEmpty {
            let marks = Array(repeating: "?", count: skus.count).joined(separator: ",")
            for r in try db.query("SELECT \(itemCols) FROM products p WHERE p.sku IN (\(marks))", skus) {
                if let s = r["sku"] as? String { product[s] = r }
            }
            for r in try db.query("SELECT sku, store, qty FROM stock WHERE sku IN (\(marks))", skus) {
                if let s = r["sku"] as? String, let st = r["store"] as? String { stock[s, default: [:]][st] = num(r["qty"]) ?? 0 }
            }
        }
        var total = 0.0, open = 0.0
        for i in rows.indices {
            let qty = num(rows[i]["qty"]) ?? 1
            guard let sku = rows[i]["sku"] as? String else { continue }
            if var p = product[sku] {
                p["labels"] = ((p["labels"] as? String) ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
                p["store_qty"] = stock[sku]?[store] ?? 0
                rows[i]["product"] = p
                if let price = num(p["price"]) {
                    total += price * qty
                    if (rows[i]["checked"] as? Int ?? 0) == 0 { open += price * qty }
                }
            }
        }
        // dostupnost po prodejnách pro položky, které ještě nejsou v košíku
        let pending = rows.filter { ($0["checked"] as? Int ?? 0) == 0 && $0["sku"] is String }
        var stores: [[String: Any]] = []
        if let db {
            for s in try db.query("SELECT code, name FROM stores ORDER BY name") {
                guard let code = s["code"] as? String else { continue }
                let have = pending.filter { r in
                    guard let sku = r["sku"] as? String else { return false }
                    return (stock[sku]?[code] ?? 0) >= (num(r["qty"]) ?? 1)
                }.count
                stores.append(["code": code, "name": s["name"] ?? code, "have": have])
            }
        }
        return ["id": listID, "name": list["name"] ?? "", "store": store, "items": rows,
                "stores": stores, "pending": pending.count, "total": total, "open_total": open]
    }

    /// Hlídané produkty, které jsou znovu skladem na mé prodejně nebo v e-shopu (od posledního upozornění).
    func newWatchedRestocks() throws -> [String] {
        guard let db, caps.restock else { return [] }
        let store = setting("store") ?? "888"
        let rows = try db.query("""
            SELECT p.sku, p.name, MAX(r.day) AS day FROM u.watch w JOIN products p ON p.sku = w.sku
            JOIN restock r ON r.sku = w.sku AND r.store IN (?, 'eshop')
            WHERE r.day > COALESCE(w.notified_restock, w.added) GROUP BY p.sku
            """, [store])
        for r in rows { try db.run("UPDATE u.watch SET notified_restock = ? WHERE sku = ?", [r["day"], r["sku"]]) }
        return rows.compactMap { $0["name"] as? String }
    }

    /// Hlídané produkty, které zlevnily a ještě o nich nepřišlo upozornění.
    func newWatchedDrops() throws -> [(name: String, price: Double, was: Double)] {
        guard let db else { return [] }
        let rows = try db.query("""
            SELECT p.sku, p.name, p.price, w.added_price FROM u.watch w JOIN products p ON p.sku = w.sku
            WHERE (p.price < w.added_price OR (w.target IS NOT NULL AND p.price <= w.target))
              AND (w.notified_price IS NULL OR p.price < w.notified_price)
            """)
        for r in rows { try db.run("UPDATE u.watch SET notified_price = ? WHERE sku = ?", [r["price"], r["sku"]]) }
        return rows.compactMap { r in
            guard let n = r["name"] as? String, let p = r["price"] as? Double else { return nil }
            return (n, p, r["added_price"] as? Double ?? p)
        }
    }
}
