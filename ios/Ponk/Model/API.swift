import CryptoKit
import Foundation
import Observation

enum APIError: LocalizedError {
    case noServer
    case badURL
    case offline
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noServer: return "Nejdřív v sekci Více zadej adresu serveru Ponk."
        case .badURL: return "Adresa serveru není platná. Má vypadat třeba jako 192.168.1.20:8765."
        case .offline: return "Server Ponk není dostupný. Jsi doma na Wi-Fi a běží na počítači python run.py?"
        case .server(let msg): return msg
        }
    }
}

/// Klient lokálního serveru. Každou úspěšnou odpověď si uloží, takže mimo domov
/// aplikace ukáže poslední známá data (s upozorněním, odkdy jsou).
@MainActor
@Observable
final class PonkAPI {
    static let shared = PonkAPI()

    /// Když jsou data z mezipaměti, je tu čas jejich uložení.
    var offlineSince: Date?

    private let decoder = JSONDecoder()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    var server: String { UserDefaults.standard.string(forKey: "server") ?? "" }

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ponk-api", isDirectory: true)
    }

    func url(_ path: String, _ query: Query = [:], server override: String? = nil) throws -> URL {
        var base = (override ?? server).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { throw APIError.noServer }
        if !base.lowercased().hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard var comps = URLComponents(string: base + "/api/" + path) else { throw APIError.badURL }
        if !query.isEmpty {
            comps.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        // "+" by server četl jako mezeru (hledání "ONE+")
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let u = comps.url else { throw APIError.badURL }
        return u
    }

    func get<T: Decodable>(_ path: String, _ query: Query = [:], as type: T.Type = T.self) async throws -> T {
        let u = try url(path, query)
        let file = cacheDir.appendingPathComponent(cacheKey(u))
        do {
            let (data, response) = try await session.data(from: u)
            try check(response, data)
            let value = try decoder.decode(T.self, from: data)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            offlineSince = nil
            return value
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            if let data = try? Data(contentsOf: file), let value = try? decoder.decode(T.self, from: data) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                offlineSince = (attrs?[.modificationDate] as? Date) ?? Date()
                return value
            }
            throw APIError.offline
        }
    }

    func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        var req = URLRequest(url: try url(path))
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await session.data(for: req)
            try check(response, data)
        } catch is URLError {
            throw APIError.offline
        }
    }

    /// Ověří adresu serveru dřív, než ji uložíme.
    func test(server candidate: String) async throws -> Meta {
        let u = try url("meta", server: candidate)
        do {
            let (data, response) = try await session.data(from: u)
            try check(response, data)
            return try decoder.decode(Meta.self, from: data)
        } catch is URLError {
            throw APIError.offline
        }
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw APIError.server(msg ?? "Server vrátil chybu \(http.statusCode).")
    }

    private func cacheKey(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

/// Sdílený stav aplikace: metadata ze serveru (prodejny, nastavení, stav kontroly cen).
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
