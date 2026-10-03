import CoreGraphics
import Foundation

// Názvy vlastností záměrně kopírují JSON z lokálního serveru (snake_case),
// aby nebylo potřeba převádět klíče. Server: ponk/server.py, ponk/search.py.

typealias Query = [String: String]

/// Hodnota v JSON, která může být text, číslo nebo bool – vždy ji chceme jako text (parametry hledání).
struct StringMap: Codable, Hashable {
    var values: Query

    init(_ values: Query) { self.values = values }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode([String: Scalar].self)) ?? [:]
        values = raw.compactMapValues { $0.text }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    private enum Scalar: Decodable {
        case text(String), number(Double), flag(Bool), none

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .none }
            else if let v = try? c.decode(String.self) { self = .text(v) }
            else if let v = try? c.decode(Double.self) { self = .number(v) }
            else if let v = try? c.decode(Bool.self) { self = .flag(v) }
            else { self = .none }
        }

        var text: String? {
            switch self {
            case .text(let v): return v
            case .number(let v): return v.rounded() == v ? String(Int(v)) : String(v)
            case .flag(let v): return v ? "1" : "0"
            case .none: return nil
            }
        }
    }
}

struct Item: Codable, Identifiable, Hashable {
    let sku: String
    let name: String
    let brand: String?
    let image: String?
    let price: Double?
    let was_price: Double?
    let min30_price: Double?
    let real_discount: Int?
    let labels: [String]
    let online_in_stock: Int?
    let unit_price: Double?
    let unit: String?
    let rating: Int?
    let prev_price: Double?
    let price_changed_at: String?
    let drop_pct: Double?
    let cat3: String?
    let dims: String?
    let store_qty: Double?
    // jen v seznamu hlídaných
    let added: String?
    let added_price: Double?
    let target: Double?
    // novější data: produkt stažený z nabídky (bez ceny) a jeho poslední cena
    var active: Int? = nil
    var last_price: Double? = nil

    var id: String { sku }
    var isListed: Bool { active != 0 }
}

struct Store: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    let city: String?
    var id: String { code }
}

struct RunInfo: Codable, Hashable {
    let id: Int
    let started: String?
    let finished: String?
    let status: String?
    let products: Int?
    let changed: Int?
}

struct SyncStatus: Codable, Hashable, Sendable {
    let running: Bool
    let phase: String
    let done: Int
    let total: Int
    let started: String?
    let message: String

    var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
}

struct Meta: Codable {
    let settings: [String: String]
    let stores: [Store]
    let last_run: RunInfo?
    let products: Int
    let last_change: String?
    let watched_drops: Int
    let labels: [String: String]
    let sync: SyncStatus
    let version: String?
}

struct FacetValue: Codable, Hashable, Identifiable {
    let value: String
    let count: Int
    var id: String { value }
}

struct CategoryFacet: Codable, Hashable {
    let level: String
    let values: [FacetValue]
}

struct PriceRange: Codable, Hashable {
    let min: Double?
    let max: Double?
}

struct LabelFacet: Codable, Hashable, Identifiable {
    let value: String
    let label: String
    let count: Int
    var id: String { value }
}

struct AttrFacet: Codable, Hashable, Identifiable {
    let code: String
    let label: String
    let values: [FacetValue]
    var id: String { code }
}

struct Facets: Codable, Hashable {
    let categories: CategoryFacet
    let brands: [FacetValue]
    let price: PriceRange
    let labels: [LabelFacet]
    let attrs: [AttrFacet]
}

struct SearchResponse: Codable {
    let total: Int
    let page: Int
    let pages: Int
    let items: [Item]
    let facets: Facets?
}

struct HomeSection: Codable, Identifiable {
    let title: String
    let query: StringMap
    let items: [Item]
    var id: String { title }
}

struct HomeResponse: Codable {
    let sections: [HomeSection]
    let watched_drops: Int
}

struct CategoryValue: Codable, Hashable, Identifiable {
    let value: String
    let count: Int
    let image: String?
    var id: String { value }
}

struct CategoriesResponse: Codable {
    let level: String
    let values: [CategoryValue]
}

struct SuggestProduct: Codable, Hashable, Identifiable {
    let sku: String
    let name: String
    let price: Double?
    let image: String?
    var id: String { sku }
}

struct SuggestCategory: Codable, Hashable, Identifiable {
    let cat1: String?
    let cat2: String?
    let cat3: String?
    let name: String
    let count: Int
    var id: String { [cat1, cat2, cat3].compactMap { $0 }.joined(separator: "/") }

    var query: Query {
        var q = Query()
        q["cat1"] = cat1
        q["cat2"] = cat2
        q["cat3"] = cat3
        return q
    }
}

struct SuggestResponse: Codable {
    let products: [SuggestProduct]
    let categories: [SuggestCategory]
    let brands: [String]
}

struct Position: Codable, Hashable {
    let shelf: String?
    let field: String?
    let zone: String?
}

struct PricePoint: Codable, Hashable {
    let day: String
    let price: Double
}

struct Param: Codable, Hashable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct WatchInfo: Codable, Hashable {
    let sku: String
    let added: String?
    let added_price: Double?
    let target: Double?
}

struct ProductDetail: Codable {
    let sku: String
    let name: String
    let brand: String?
    let url_path: String?
    let cat_path: [String]
    let image: String?
    let gallery: [String]
    let price: Double?
    let was_price: Double?
    let min30_price: Double?
    let real_discount: Int?
    let labels: [String]
    let online_qty: Double?
    let online_in_stock: Int?
    let unit_price: Double?
    let unit: String?
    let rating: Int?
    let ean: String?
    let usps: [String]
    let dims: String?
    let positions: [String: Position]
    let first_seen: String?
    let prev_price: Double?
    let price_changed_at: String?
    let description: String?
    let history: [PricePoint]
    let stock: [String: Double]
    let params: [Param]
    let watch: WatchInfo?
    var active: Int? = nil
    var last_price: Double? = nil

    var pictures: [String] {
        var out: [String] = []
        for p in [image].compactMap({ $0 }) + gallery where !out.contains(p) { out.append(p) }
        return Array(out.prefix(12))
    }
}

struct SavedSearch: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let query: StringMap
    let fresh: Int
    let total: Int
}

struct ListResponse<T: Codable>: Codable {
    let items: [T]
}

// --- navigace ---------------------------------------------------------------

struct ProductRoute: Hashable { let sku: String }

struct ResultsRoute: Hashable {
    var query: Query
    var title: String
    var savedID: Int? = nil
}

struct CategoryRoute: Hashable {
    var cat1: String?
    var cat2: String?
}

struct StoreMapLabel: Codable, Hashable {
    let lo: Int
    let hi: Int
    let x: Double, y: Double, w: Double, h: Double
    let zx: Double?, zy: Double?, zw: Double?, zh: Double?

    var box: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    var zone: CGRect? {
        guard let zx, let zy, let zw, let zh else { return nil }
        return CGRect(x: zx, y: zy, width: zw, height: zh)
    }
}

struct StoreMap: Codable {
    let store: String
    let image: String
    let width: Double
    let height: Double
    let labels: [StoreMapLabel]
}
