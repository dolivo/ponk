import Foundation
import SQLite3

/// Tenká obálka nad SQLite (je součástí iOS). Řádky vrací jako slovníky
/// s hodnotami Int64 / Double / String / NSNull, takže jdou rovnou do JSON.
final class SQLiteDB {
    enum DBError: Error, LocalizedError {
        case open(String), prepare(String, String), step(String)
        var errorDescription: String? {
            switch self {
            case .open(let m): return "Databázi nejde otevřít: \(m)"
            case .prepare(let m, let sql): return "Chyba dotazu: \(m) (\(sql.prefix(80)))"
            case .step(let m): return "Chyba databáze: \(m)"
            }
        }
    }

    private(set) var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    /// Připravené dotazy se znovu používají (stejné SQL se neparsuje pořád dokola).
    private var statements: [String: OpaquePointer] = [:]
    /// Názvy sloupců připraveného dotazu (nepřevádí se z C řetězců při každém volání).
    private var columnNames: [OpaquePointer: [String]] = [:]
    private static let maxCachedStatements = 96

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "?"
            sqlite3_close(handle)
            handle = nil
            throw DBError.open(msg)
        }
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit { close() }

    func close() {
        for stmt in statements.values { sqlite3_finalize(stmt) }
        statements.removeAll()
        columnNames.removeAll()
        if let h = handle { sqlite3_close_v2(h) }
        handle = nil
    }

    private var message: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "zavřeno" }

    func exec(_ sql: String) throws {
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK { throw DBError.step(message) }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer? {
        let stmt: OpaquePointer?
        if let cached = statements[sql] {
            stmt = cached
        } else {
            var fresh: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &fresh, nil) == SQLITE_OK else {
                sqlite3_finalize(fresh)
                throw DBError.prepare(message, sql)
            }
            if statements.count >= Self.maxCachedStatements {
                for s in statements.values { sqlite3_finalize(s) }
                statements.removeAll()
                columnNames.removeAll()
            }
            statements[sql] = fresh
            stmt = fresh
        }
        bind(stmt, args)
        return stmt
    }

    /// Vrátí dotaz do výchozího stavu, aby šel použít znovu (místo sqlite3_finalize).
    private func done(_ stmt: OpaquePointer?) {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    private func bind(_ stmt: OpaquePointer?, _ args: [Any?]) {
        for (i, value) in args.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil, is NSNull: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLiteDB.transient)
            default: sqlite3_bind_text(stmt, idx, "\(value!)", -1, SQLiteDB.transient)
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) throws -> Int {
        let stmt = try prepare(sql, args)
        defer { done(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(message) }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ args: [Any?] = []) throws -> [[String: Any]] {
        let stmt = try prepare(sql, args)
        defer { done(stmt) }
        var rows: [[String: Any]] = []
        let n = sqlite3_column_count(stmt)
        let names: [String]
        if let stmt, let cached = columnNames[stmt] {
            names = cached
        } else {
            names = (0..<n).map { String(cString: sqlite3_column_name(stmt, $0)) }
            if let stmt { columnNames[stmt] = names }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError.step(message) }
            var row = [String: Any](minimumCapacity: Int(n))
            for i in 0..<n {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[names[Int(i)]] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row[names[Int(i)]] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[names[Int(i)]] = String(cString: sqlite3_column_text(stmt, i))
                default: row[names[Int(i)]] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }

    func scalar(_ sql: String, _ args: [Any?] = []) throws -> Any? {
        let stmt = try prepare(sql, args)
        defer { done(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        switch sqlite3_column_type(stmt, 0) {
        case SQLITE_INTEGER: return Int(sqlite3_column_int64(stmt, 0))
        case SQLITE_FLOAT: return sqlite3_column_double(stmt, 0)
        case SQLITE_TEXT: return String(cString: sqlite3_column_text(stmt, 0))
        default: return nil
        }
    }

    /// Projde výsledek řádek po řádku bez vytváření slovníků (pro velké průchody).
    /// V `body` se čte přímo ze sloupců přes sqlite3_column_*.
    func each(_ sql: String, _ args: [Any?] = [], _ body: (OpaquePointer) throws -> Void) throws {
        guard let stmt = try prepare(sql, args) else { return }
        defer { done(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError.step(message) }
            try body(stmt)
        }
    }

    /// Hromadné vložení (id, n) do pomocné tabulky v jedné transakci, bez převodů přes Any.
    func insertPairs(_ sql: String, ids: UnsafeBufferPointer<Int64>, counts: UnsafeBufferPointer<UInt8>?) throws {
        guard let stmt = try prepare(sql, []) else { return }
        defer { done(stmt) }
        try exec("BEGIN")
        for i in 0..<ids.count {
            sqlite3_bind_int64(stmt, 1, ids[i])
            if let counts { sqlite3_bind_int64(stmt, 2, Int64(counts[i])) }
            let rc = sqlite3_step(stmt)
            sqlite3_reset(stmt)
            if rc != SQLITE_DONE {
                let error = DBError.step(message)
                try? exec("ROLLBACK")
                throw error
            }
        }
        try exec("COMMIT")
    }

    /// Hromadné vložení (id, text) – příprava vyhledávacího textu po stažení dat.
    func insertText(_ sql: String, _ next: () -> (Int64, UnsafeBufferPointer<UInt8>)?) throws {
        guard let stmt = try prepare(sql, []) else { return }
        defer { done(stmt) }
        while let (id, text) = next() {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_bind_text(stmt, 2, UnsafeRawPointer(text.baseAddress)?.assumingMemoryBound(to: CChar.self), Int32(text.count), SQLiteDB.transient)
            let rc = sqlite3_step(stmt)
            sqlite3_reset(stmt)
            if rc != SQLITE_DONE { throw DBError.step(message) }
        }
    }

    /// Stejný příkaz pro mnoho řádků (jedna příprava, jen se mění hodnoty).
    func runMany(_ sql: String, _ rows: [[Any?]]) throws {
        for args in rows {
            let stmt = try prepare(sql, args)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE && rc != SQLITE_ROW {
                let error = DBError.step(message)
                done(stmt)
                throw error
            }
            done(stmt)
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN")
        do { try body(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }
}
