import Foundation

/// Naposledy hledané výrazy a prohlížené produkty (jen v telefonu).
/// Ukládají se jako text oddělený „|“, aby šly použít přímo s @AppStorage.
enum Recents {
    static let searchesKey = "recent_searches"
    static let viewedKey = "recent_viewed"

    static func list(_ raw: String) -> [String] {
        raw.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    /// Vrátí nový seznam s hodnotou na začátku (bez duplicit, nejvýš `limit` položek).
    static func adding(_ value: String, to raw: String, limit: Int = 10) -> String {
        let v = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: " ")
        guard !v.isEmpty else { return raw }
        let rest = list(raw).filter { $0.caseInsensitiveCompare(v) != .orderedSame }
        return ([v] + rest).prefix(limit).joined(separator: "|")
    }

    static func addViewed(_ sku: String) {
        let d = UserDefaults.standard
        d.set(adding(sku, to: d.string(forKey: viewedKey) ?? "", limit: 20), forKey: viewedKey)
    }
}
