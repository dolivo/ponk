import Foundation
import Observation

enum APIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let msg): return msg
        }
    }
}

/// Vstupní bod pro obrazovky. Dřív posílal dotazy na server v počítači, teď je
/// vyřizuje databáze v telefonu (LocalEngine) a u detailu produktu živě bauhaus.cz.
/// Cesty i JSON zůstaly stejné, takže obrazovky se nemusely měnit.
@MainActor
@Observable
final class PonkAPI {
    static let shared = PonkAPI()

    /// Když jsou data starší než dva dny, je tu datum jejich přípravy (zobrazí se upozornění).
    var offlineSince: Date?

    private let decoder = JSONDecoder()

    func get<T: Decodable>(_ path: String, _ query: Query = [:], as type: T.Type = T.self) async throws -> T {
        let store = DataStore.shared
        if path == "sync" {
            return try decoder.decode(T.self, from: JSONEncoder().encode(store.status))
        }
        var data = try await store.engine.handleJSON(method: "GET", path: path, query: query, body: nil)
        if path == "meta", var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["sync"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.status))
            data = try JSONSerialization.data(withJSONObject: dict)
        }
        if path.hasPrefix("product/"), let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let enriched = await BauhausLive.enrich(dict)
            data = try JSONSerialization.data(withJSONObject: enriched)
        }
        return try decoder.decode(T.self, from: data)
    }

    func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        if path == "sync" {
            if method == "POST" { Task { await DataStore.shared.update(force: true) } }
            return
        }
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await DataStore.shared.engine.handleJSON(method: method, path: path, query: [:], body: bodyData)
        if method == "POST", path == "watch" { DataStore.shared.requestNotifications() }
    }
}

/// Sdílený stav aplikace: metadata (prodejny, nastavení, stav dat).
@MainActor
@Observable
final class AppModel {
    var meta: Meta?
    var metaError: String?
    let api = PonkAPI.shared

    func loadMeta() async {
        do {
            meta = try await api.get("meta", as: Meta.self)
            metaError = nil
        } catch {
            metaError = error.localizedDescription
        }
    }

    var myStore: String? { meta?.settings["store"] }

    func storeName(_ code: String?) -> String {
        guard let code else { return "" }
        return meta?.stores.first { $0.code == code }?.name ?? code
    }

    func labelName(_ key: String) -> String { meta?.labels[key] ?? key }
}
