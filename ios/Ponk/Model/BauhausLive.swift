import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Živé dotazy přímo na bauhaus.cz pro detail produktu: aktuální cena, sklad na
/// prodejnách, regál, fotky a popis. Když telefon není online, detail ukáže data
/// ze stažené databáze.
enum BauhausLive {
    static let catalog = URL(string: "https://www.bauhaus.cz/api/catalog/vue_storefront_catalog/product/_search")!
    static let stocks = URL(string: "https://www.bauhaus.cz/api/ext/vaimo-storelocator/stocks-api/indice/vue_storefront_catalog/stocksBySkus")!
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }()

    private static func post(_ url: URL, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Ponk/iOS (open-source)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double, d > 0 { return d }
        if let i = v as? Int, i > 0 { return Double(i) }
        if let s = v as? String, let d = Double(s), d > 0 { return d }
        return nil
    }

    /// Doplní detail produktu (JSON slovník ze stažené databáze) o živá data.
    static func enrich(_ product: [String: Any]) async -> [String: Any] {
        guard let sku = product["sku"] as? String else { return product }
        var p = product
        async let docTask = post(catalog, [
            "size": 1,
            "query": ["term": ["sku": sku]],
            "_source": ["excludes": ["product_links", "classification_store_sort", "producersjson", "configurable_children", "tier_prices"]],
        ])
        async let stockTask = post(stocks, ["skus": [sku]])

        if let res = try? await docTask,
           let hits = (res["hits"] as? [String: Any])?["hits"] as? [[String: Any]],
           let src = hits.first?["_source"] as? [String: Any] {
            if let price = num(src["final_price_incl_tax"]) ?? num(src["price_incl_tax"]) ?? num(src["regular_price"]) {
                p["price"] = price
            }
            if let hmp = src["history_min_price"] as? [String: Any] {
                if let m = num(hmp["min_price"]) { p["min30_price"] = m }
                if let d = hmp["percentage_discount"] as? Int { p["real_discount"] = d }
            }
            if let stock = src["stock"] as? [String: Any] {
                p["online_qty"] = num(stock["qty"]) ?? 0
                p["online_in_stock"] = (stock["is_in_stock"] as? Bool ?? false) ? 1 : 0
            }
            var gallery: [String] = []
            if let main = (src["image_webp"] ?? src["image"]) as? String { gallery.append(main) }
            for g in src["media_gallery"] as? [[String: Any]] ?? [] where (g["typ"] as? String ?? "image") == "image" {
                if let path = (g["image_webp"] ?? g["image"]) as? String, !gallery.contains(path) { gallery.append(path) }
            }
            if !gallery.isEmpty { p["gallery"] = gallery }
            let usps = (1...5).compactMap { src["usp\($0)"] as? String }.filter { !$0.isEmpty }
            if !usps.isEmpty { p["usps"] = usps }
            if let d = src["description"] as? String, !d.isEmpty { p["description"] = d }
            var positions: [String: Any] = [:]
            for (store, rows) in src["position_in_store_array"] as? [String: Any] ?? [:] {
                guard let r = (rows as? [[String: Any]])?.first, let shelf = r["shelf"] as? String, !shelf.isEmpty else { continue }
                var zone = (r["description"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                if zone.range(of: "^R\\d+\\s+F\\d+", options: .regularExpression) != nil { zone = "" }
                positions[store] = ["shelf": shelf, "field": r["field"] as? String ?? "", "zone": zone]
            }
            if !positions.isEmpty { p["positions"] = positions }
            p["live"] = true
        }
        if let res = try? await stockTask, let rows = res["result"] as? [[String: Any]] {
            var stock: [String: Any] = [:]
            for r in rows where "\(r["status"] ?? "1")" == "1" {
                if let code = r["code"] as? String, let q = num(r["qty"]) { stock[code] = q }
            }
            p["stock"] = stock
        }
        return p
    }
}
