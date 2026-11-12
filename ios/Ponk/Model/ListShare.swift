import Foundation
import Observation

/// Sdílení nákupního seznamu odkazem bez serveru: celý seznam je zabalený přímo v odkazu
/// ponk://import?d=… (JSON → zlib → base64url). Druhý telefon ho klepnutím nebo vložením
/// ze schránky načte a sloučí se stejným seznamem (podle trvalého id seznamu).
enum ListShare {
    struct Payload: Codable {
        var v = 1
        let sid: String
        let n: String
        let s: String?
        /// položky: [kód produktu, vlastní text, množství, odškrtnuto 0/1]
        let i: [Item]

        struct Item: Codable {
            let sku: String?
            let text: String?
            let qty: Double
            let checked: Int

            init(sku: String?, text: String?, qty: Double, checked: Int) {
                self.sku = sku; self.text = text; self.qty = qty; self.checked = checked
            }
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                sku = try c.decodeNil() ? nil : try c.decode(String.self)
                text = try c.decodeNil() ? nil : try c.decode(String.self)
                qty = try c.decode(Double.self)
                checked = try c.decode(Int.self)
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                if let sku { try c.encode(sku) } else { try c.encodeNil() }
                if let text { try c.encode(text) } else { try c.encodeNil() }
                try c.encode(qty)
                try c.encode(checked)
            }
        }
    }

    static func url(_ p: Payload) -> URL? {
        guard let json = try? JSONEncoder().encode(p),
              let z = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        let b64 = z.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "ponk://import?d=\(b64)")
    }

    static func decode(_ url: URL) -> Payload? {
        guard url.scheme == "ponk", url.host == "import",
              let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        var b64 = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let z = Data(base64Encoded: b64),
              let json = try? (z as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: json)
    }

    /// Najde odkaz na sdílený seznam v libovolném textu (zpráva vložená ze schránky).
    static func find(in text: String) -> Payload? {
        guard let r = text.range(of: #"ponk://import\?d=[A-Za-z0-9_\-]+"#, options: .regularExpression),
              let url = URL(string: String(text[r])) else { return nil }
        return decode(url)
    }
}

/// Sdílený seznam čekající na potvrzení (přišel odkazem, když byla aplikace v jiné záložce).
@Observable
@MainActor
final class ShareInbox {
    static let shared = ShareInbox()
    var pending: ListShare.Payload?
}
