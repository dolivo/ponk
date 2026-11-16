import Foundation
import Security

/// Co aplikace posílá widgetu „Můj Bauhaus“: hlídané, aktuální nákupní seznam a novinky
/// skladem ve zvolené prodejně. Počítá se v aplikaci (z její databáze), widget jen zobrazuje.
struct WidgetSnapshot: Codable {
    struct Product: Codable, Hashable {
        let sku: String
        let name: String
        let price: Double?
        let image: String?
        /// o kolik Kč zlevnil od přidání do hlídaných
        let drop: Double?
    }

    struct ListInfo: Codable, Hashable {
        let id: Int
        let name: String
        let done: Int
        let total: Int
        let sum: Double
    }

    var updated: Date?
    let storeName: String
    let watchTotal: Int
    let watchDropped: Int
    let watchTop: Product?
    let list: ListInfo?
    /// den poslední novinky skladem (yyyy-MM-dd)
    let restockDay: String?
    let restockCount: Int
    let restock: [Product]
}

/// Předání dat widgetu přes Klíčenku. Aplikace i widget podepisuje Feather stejným profilem,
/// takže sdílejí stejnou skupinu Klíčenky (sdílená složka App Group by vyžadovala zvláštní
/// oprávnění v certifikátu). Data jsou malá (pár kB) a nic tajného neobsahují.
enum WidgetShare {
    private static let service = "cz.ponk.widget"
    private static let account = "snapshot"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add.merge(attrs) { $1 }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> WidgetSnapshot? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
