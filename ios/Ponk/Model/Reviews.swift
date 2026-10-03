import Foundation

/// Recenze zákazníků z API BAUHAUS (stejné jako na bauhaus.cz). Recenze sdílí všechny
/// země BAUHAUS (bauhaus.info, .at, .ch…); zahraniční mají český překlad.
struct Review: Identifiable, Hashable {
    let id: String
    let author: String
    let rating: Int          // 1–5
    let date: String         // yyyy-MM-dd
    let title: String
    let text: String
    let original: String?    // původní text, když je recenze přeložená
    let country: String
    let source: String
    let verified: Bool
    let recommended: Bool
    let replies: [String]
}

struct ReviewsPage {
    var count = 0
    var average = 0.0
    var distribution: [Int] = [0, 0, 0, 0, 0] // 5, 4, 3, 2, 1 hvězdičky
    var total = 0
    var next: String?
    var items: [Review] = []
}

enum ReviewsAPI {
    static let base = "https://www.bauhaus.cz/api/ext/vaimo-reviews/reviews/"

    private static let countries = [
        "de": "Německo", "at": "Rakousko", "ch": "Švýcarsko", "cz": "Česko", "sk": "Slovensko",
        "hr": "Chorvatsko", "si": "Slovinsko", "hu": "Maďarsko", "dk": "Dánsko", "se": "Švédsko",
        "fi": "Finsko", "no": "Norsko", "is": "Island", "lu": "Lucembursko", "tr": "Turecko",
    ]

    static func load(sku: String, cursor: String? = nil, limit: Int = 10) async throws -> ReviewsPage {
        let c = (cursor?.isEmpty == false ? cursor! : "false")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "false"
        guard let url = URL(string: "\(base)getReviews/product_id/\(sku)/limit/\(limit)/cursor/\(c)/ratings/false") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Ponk/iOS (open-source)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await BauhausLive.session.data(for: req)
        let root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return parse(root["result"] as? [String: Any] ?? [:])
    }

    /// (text v češtině, originál – jen když je recenze přeložená)
    private static func pick(_ parts: Any?) -> (String, String?) {
        let list = parts as? [[String: Any]] ?? []
        let cs = list.first { $0["locale"] as? String == "cs-CZ" }
        let orig = list.first { $0["original"] as? Bool == true }
        let text = ((cs ?? orig)?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var original: String?
        if let orig, cs != nil, (orig["locale"] as? String) != "cs-CZ" {
            original = (orig["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (plainText(fromHTML: text), original.map { plainText(fromHTML: $0) })
    }

    static func parse(_ r: [String: Any]) -> ReviewsPage {
        var page = ReviewsPage()
        let all = (r["ratings"] as? [[String: Any]] ?? []).first { $0["collection_source"] as? String == "all" }
        page.count = all?["count"] as? Int ?? 0
        page.average = (all?["average_rating"] as? NSNumber)?.doubleValue ?? 0
        var dist: [Int: Int] = [:]
        for d in all?["rating_distribution"] as? [[String: Any]] ?? [] {
            if let s = d["rating"] as? Int { dist[s] = d["count"] as? Int ?? 0 }
        }
        page.distribution = [5, 4, 3, 2, 1].map { dist[$0] ?? 0 }
        let pag = r["pagination"] as? [String: Any] ?? [:]
        page.total = pag["filtered_total"] as? Int ?? 0
        let next = (pag["cursor"] as? [String: Any])?["next"] as? String
        page.next = (next?.isEmpty ?? true) ? nil : next
        page.items = (r["reviews"] as? [[String: Any]] ?? []).compactMap { v in
            let (title, _) = pick(v["title"])
            let (text, original) = pick(v["text"])
            guard !text.isEmpty || !title.isEmpty else { return nil }
            let code = (v["country_of_origin"] as? String ?? "").lowercased()
            let rawReplies = (v["replies"] as? [[String: Any]] ?? []) + (v["reply"] as? [[String: Any]] ?? [])
            let replies = rawReplies.compactMap { rep -> String? in
                let t = rep["text"] is [Any] ? pick(rep["text"]).0 : (rep["text"] as? String ?? "")
                return t.isEmpty ? nil : plainText(fromHTML: t)
            }
            return Review(
                id: v["id"] as? String ?? UUID().uuidString,
                author: (v["author"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Zákazník",
                rating: v["rating"] as? Int ?? 0,
                date: String((v["submitted_at"] as? String ?? "").prefix(10)),
                title: title, text: text, original: original,
                country: countries[code] ?? code.uppercased(),
                source: v["source"] as? String ?? "",
                verified: v["purchaser_type"] as? String == "verified",
                recommended: v["recommended"] as? String == "yes",
                replies: replies)
        }
        return page
    }
}
