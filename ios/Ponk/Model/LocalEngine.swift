import Foundation

/// Data v telefonu: stažená databáze (ceny, sklady, historie) + vlastní databáze
/// uživatele (hlídané, uložená hledání, nastavení). Odpovídá stejnými JSON strukturami
/// jako dřív server na počítači, takže obrazovky aplikace se nemusely měnit.
actor LocalEngine {
    static let labels: [String: String] = [
        "sell_off": "Výprodej", "sale": "Akce", "free_shipping": "Doprava zdarma", "only_online": "Jen online",
        "warranty": "Prodloužená záruka", "qty_discount": "Množstevní sleva", "new": "Novinka",
    ]
    static let labelOrder = ["sell_off", "sale", "free_shipping", "only_online", "warranty", "qty_discount", "new"]
    static let pageSize = 30

    private var db: SQLiteDB?
    private let dataPath: String
    private let userPath: String

    init(dataPath: String, userPath: String) {
        self.dataPath = dataPath
        self.userPath = userPath
    }

    var hasData: Bool { db != nil }

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
            """)
        user.close()
        guard FileManager.default.fileExists(atPath: dataPath) else { return }
        let d = try SQLiteDB(path: dataPath)
        try d.run("ATTACH DATABASE ? AS u", [userPath])
        db = d
    }

    func closeData() {
        db?.close()
        db = nil
    }

    /// Po stažení: doplní vyhledávací sloupec a indexy (v souboru nejsou kvůli velikosti).
    static func prepareDownloaded(path: String) throws {
        let d = try SQLiteDB(path: path)
        defer { d.close() }
        let cols = try d.query("PRAGMA table_info(products)").compactMap { $0["name"] as? String }
        if !cols.contains("search") { try d.exec("ALTER TABLE products ADD COLUMN search TEXT") }
        let rows = try d.query("SELECT sku, name, brand, cat2, cat3, ean FROM products")
        try d.transaction {
            for r in rows {
                let text = ["name", "brand", "cat2", "cat3", "sku", "ean"].compactMap { r[$0] as? String }.joined(separator: " ")
                try d.run("UPDATE products SET search = ? WHERE sku = ?", [fold(text), r["sku"]])
            }
        }
        try d.exec("""
            CREATE INDEX IF NOT EXISTS p_cat ON products(cat1, cat2, cat3);
            CREATE INDEX IF NOT EXISTS p_brand ON products(brand);
            CREATE INDEX IF NOT EXISTS p_price ON products(price);
            CREATE INDEX IF NOT EXISTS p_disc ON products(real_discount);
            CREATE INDEX IF NOT EXISTS p_changed ON products(price_changed_at);
            CREATE INDEX IF NOT EXISTS pa_vid ON product_attrs(vid, sku);
            CREATE INDEX IF NOT EXISTS av_code ON attr_values(code, value);
            CREATE INDEX IF NOT EXISTS stock_store ON stock(store, sku);
            ANALYZE;
            """)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ")).lowercased()
    }

    // MARK: - směrování (stejné cesty jako REST API serveru)

    /// Totéž co handle(), ale vrací rovnou JSON (bezpečné předávání mezi vlákny).
    func handleJSON(method: String, path: String, query: [String: String], body: Data?) throws -> Data {
        let b = try body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return try JSONSerialization.data(withJSONObject: try handle(method: method, path: path, query: query, body: b))
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
        case ("POST", "watch"):
            let sku = body?["sku"] as? String ?? ""
            let price = try data().scalar("SELECT price FROM products WHERE sku = ?", [sku])
            try user.run("INSERT OR REPLACE INTO \(t("watch")) VALUES(?, ?, ?, ?, NULL)",
                         [sku, Self.today(), price, body?["target"] as? Double ?? (body?["target"] as? Int).map(Double.init)])
            return ["ok": true]
        case ("DELETE", "watch"):
            try user.run("DELETE FROM \(t("watch")) WHERE sku = ?", [parts.count > 1 ? parts[1] : ""])
            return ["ok": true]
        case ("GET", "saved"): return ["items": try savedItems()]
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

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

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
            SELECT COUNT(*) FROM u.watch w JOIN products p ON p.sku = w.sku
            WHERE p.price < w.added_price OR (w.target IS NOT NULL AND p.price <= w.target)
            """) ?? 0
        if let v = info("server_version") { out["version"] = v }
        return out
    }

    // MARK: - filtry (port ponk/search.py → build_where)

    private func many(_ q: [String: String], _ key: String) -> [String] {
        (q[key] ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    private func buildWhere(_ q: [String: String], skip: Set<String> = []) -> (String, [Any?]) {
        var w = ["p.price IS NOT NULL"]
        var a: [Any?] = []
        let text = Self.fold(q["q"] ?? "")
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-+._")).inverted)
            .filter { !$0.isEmpty }.prefix(8)
        for tok in tokens { w.append("p.search LIKE ?"); a.append("%\(tok)%") }
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
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            w.append("p.price_changed_at >= ? AND p.drop_pct > 0"); a.append(f.string(from: since))
        }
        if let v = q["drop_min"].flatMap(Double.init) { w.append("p.drop_pct >= ?"); a.append(v) }
        if q["unit"] == "1" { w.append("p.unit_price IS NOT NULL") }
        if let v = q["since"], !v.isEmpty {
            w.append("(p.first_seen > ? OR (p.price_changed_at > ? AND p.drop_pct > 0))"); a += [v, v]
        }
        if q["watch"] == "1" { w.append("p.sku IN (SELECT sku FROM u.watch)") }
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
        "relevance": "p.rank DESC, COALESCE(p.real_discount, 0) DESC, p.name",
        "price_asc": "p.price ASC",
        "price_desc": "p.price DESC",
        "discount": "COALESCE(p.real_discount, 0) DESC, COALESCE(p.drop_pct, 0) DESC",
        "drop": "(p.price_changed_at IS NOT NULL AND p.drop_pct > 0) DESC, p.price_changed_at DESC, p.drop_pct DESC",
        "unit": "p.unit_price IS NULL, p.unit_price ASC",
        "rating": "COALESCE(p.rating, 0) DESC",
        "newest": "p.created DESC",
    ]

    private static let itemCols = """
        p.sku, p.name, p.brand, p.image, p.price, p.was_price, p.min30_price, p.real_discount, p.labels,
        p.online_in_stock, p.unit_price, p.unit, p.rating, p.prev_price, p.price_changed_at, p.drop_pct, p.cat3, p.dims
        """

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

    // MARK: - hledání + fasety

    private func search(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        let page = max(1, Int(q["page"] ?? "1") ?? 1)
        let order = Self.sorts[q["sort"] ?? "relevance"] ?? Self.sorts["relevance"]!
        let store = (q["store"].flatMap { $0.isEmpty ? nil : $0 }) ?? setting("store")
        let (w, a) = buildWhere(q)
        let total = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
        let rows = try db.query("SELECT \(Self.itemCols) FROM products p WHERE \(w) ORDER BY \(order) LIMIT ? OFFSET ?",
                                a + [Self.pageSize, (page - 1) * Self.pageSize])
        var out: [String: Any] = ["total": total, "page": page, "pages": (total + Self.pageSize - 1) / Self.pageSize,
                                  "items": try itemsFor(rows, store: store)]
        if q["facets"] != "0" { out["facets"] = try facets(q) }
        return out
    }

    private func facets(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        var f: [String: Any] = [:]
        let level = q["cat2"] != nil ? "cat3" : q["cat1"] != nil ? "cat2" : "cat1"
        var (w, a) = buildWhere(q)
        f["categories"] = ["level": level, "values": try db.query(
            "SELECT p.\(level) AS value, COUNT(*) AS count FROM products p WHERE \(w) AND p.\(level) IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 60", a)]
        (w, a) = buildWhere(q, skip: ["brand"])
        f["brands"] = try db.query(
            "SELECT p.brand AS value, COUNT(*) AS count FROM products p WHERE \(w) AND p.brand IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 300", a)
        (w, a) = buildWhere(q, skip: ["price"])
        let pr = try db.query("SELECT MIN(p.price) AS min, MAX(p.price) AS max FROM products p WHERE \(w)", a).first ?? [:]
        f["price"] = ["min": pr["min"] ?? NSNull(), "max": pr["max"] ?? NSNull()]
        (w, a) = buildWhere(q, skip: ["label"])
        var labels: [[String: Any]] = []
        for key in Self.labelOrder {
            let c = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w) AND p.labels LIKE ?", a + ["%,\(key),%"]) as? Int) ?? 0
            if c > 0 { labels.append(["value": key, "label": Self.labels[key]!, "count": c]) }
        }
        f["labels"] = labels
        var attrs: [[String: Any]] = []
        if q["cat2"] != nil || q["cat3"] != nil {
            (w, a) = buildWhere(q)
            let total = max(1, (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 1)
            let rows = try db.query("""
                SELECT av.code AS code, av.value AS value, COUNT(*) AS c FROM product_attrs pa
                JOIN attr_values av ON av.id = pa.vid JOIN products p ON p.sku = pa.sku
                WHERE \(w) GROUP BY pa.vid
                """, a)
            var groups: [String: [(String, Int)]] = [:]
            for r in rows {
                guard let code = r["code"] as? String, let value = r["value"] as? String else { continue }
                groups[code, default: []].append((value, r["c"] as? Int ?? 0))
            }
            var labelOf: [String: String] = [:]
            for r in try db.query("SELECT code, label FROM attrs") {
                if let c = r["code"] as? String { labelOf[c] = r["label"] as? String ?? c }
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
                let sorted = c.vals.sorted { Self.numericKey($0.0) < Self.numericKey($1.0) }
                attrs.append(["code": c.code, "label": labelOf[c.code]!,
                              "values": sorted.prefix(60).map { ["value": $0.0, "count": $0.1] }])
            }
        }
        f["attrs"] = attrs
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

    private func categories(_ q: [String: String]) throws -> [String: Any] {
        let db = try data()
        let c1 = q["cat1"], c2 = q["cat2"]
        if let c1, let c2 {
            return ["level": "cat3", "values": try db.query("SELECT cat3 AS value, COUNT(*) AS count, MIN(image) AS image FROM products WHERE cat1 = ? AND cat2 = ? AND cat3 IS NOT NULL GROUP BY 1 ORDER BY 1", [c1, c2])]
        }
        if let c1 {
            return ["level": "cat2", "values": try db.query("SELECT cat2 AS value, COUNT(*) AS count, MIN(image) AS image FROM products WHERE cat1 = ? AND cat2 IS NOT NULL GROUP BY 1 ORDER BY 1", [c1])]
        }
        return ["level": "cat1", "values": try db.query("SELECT cat1 AS value, COUNT(*) AS count, MIN(image) AS image FROM products WHERE cat1 IS NOT NULL GROUP BY 1 ORDER BY 2 DESC")]
    }

    private func suggest(_ text: String) throws -> [String: Any] {
        let db = try data()
        let t = Self.fold(text).trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return ["products": [], "categories": [], "brands": []] }
        let products = try db.query("SELECT sku, name, price, image FROM products WHERE search LIKE ? ORDER BY rank DESC LIMIT 6", ["%\(t)%"])
        var cats: [[String: Any]] = []
        for lvl in ["cat3", "cat2"] where cats.count < 5 {
            let group = lvl == "cat3" ? "cat1, cat2, cat3" : "cat1, cat2"
            for r in try db.query("SELECT cat1, cat2, \(lvl == "cat3" ? "cat3" : "NULL AS cat3"), COUNT(*) AS count FROM products WHERE \(lvl) IS NOT NULL GROUP BY \(group)") {
                guard let name = r[lvl] as? String, Self.fold(name).contains(t), cats.count < 5 else { continue }
                cats.append(["cat1": r["cat1"] ?? NSNull(), "cat2": r["cat2"] ?? NSNull(), "cat3": r["cat3"] ?? NSNull(),
                             "name": name, "count": r["count"] ?? 0])
            }
        }
        let brands = try db.query("SELECT DISTINCT brand FROM products WHERE brand IS NOT NULL")
            .compactMap { $0["brand"] as? String }.filter { Self.fold($0).contains(t) }.prefix(4)
        return ["products": products, "categories": cats, "brands": Array(brands)]
    }

    // MARK: - úvod, detail, hlídané

    private func home() throws -> [String: Any] {
        let db = try data()
        let store = setting("store") ?? "888"
        var sections: [[String: Any]] = []
        func add(_ title: String, _ query: [String: String], _ sql: String, _ args: [Any?] = []) throws {
            let rows = try db.query("SELECT \(Self.itemCols) FROM products p WHERE p.price IS NOT NULL AND \(sql) LIMIT 12", args)
            if !rows.isEmpty { sections.append(["title": title, "query": query, "items": try itemsFor(rows, store: store)]) }
        }
        try add("Hlídané, které zlevnily", ["watch": "1"],
                "p.sku IN (SELECT w.sku FROM u.watch w WHERE p.price < w.added_price) ORDER BY p.drop_pct DESC")
        if let last = info("last_change"), !last.isEmpty {
            try add("Zlevněno při poslední kontrole", ["drop_days": "1", "sort": "drop"],
                    "p.price_changed_at = ? AND p.drop_pct > 0 ORDER BY p.drop_pct DESC", [last])
        }
        let sname = (try db.scalar("SELECT name FROM stores WHERE code = ?", [store]) as? String) ?? store
        try add("Výprodej skladem: \(sname)", ["label": "sell_off", "store": store, "sort": "discount"],
                "p.labels LIKE '%,sell_off,%' AND EXISTS (SELECT 1 FROM stock s WHERE s.sku = p.sku AND s.store = ? AND s.qty > 0) ORDER BY COALESCE(p.real_discount, 0) DESC",
                [store])
        try add("Největší skutečné slevy", ["disc": "30", "sort": "discount"],
                "p.real_discount >= 30 ORDER BY p.real_discount DESC")
        return ["sections": sections, "watched_drops": 0]
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
        return p
    }

    private func watchItems() throws -> [[String: Any]] {
        guard let db else { return [] }
        let rows = try db.query("""
            SELECT \(Self.itemCols), w.added, w.added_price, w.target FROM u.watch w
            JOIN products p ON p.sku = w.sku ORDER BY (p.price < w.added_price) DESC, w.added DESC
            """)
        return try itemsFor(rows, store: setting("store"))
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
                var (w, a) = buildWhere(withSince)
                fresh = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
                (w, a) = buildWhere(query)
                total = (try db.scalar("SELECT COUNT(*) FROM products p WHERE \(w)", a) as? Int) ?? 0
            }
            out.append(["id": r["id"] ?? 0, "name": r["name"] ?? "", "query": query, "fresh": fresh, "total": total])
        }
        return out
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
