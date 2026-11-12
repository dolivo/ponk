import Foundation
import Observation
import Security

/// Účet na bauhaus.cz: přihlášení (přes oficiální stránku v aplikaci, Ponk heslo nevidí),
/// historie objednávek a rezervací, košík a rezervace z nákupního seznamu.
/// Používá stejné rozhraní jako web Bauhausu; token je jen v Klíčence telefonu.
@Observable
@MainActor
final class BauhausAccount {
    static let shared = BauhausAccount()
    static let base = URL(string: "https://www.bauhaus.cz")!
    static let checkoutBase = "https://kosik.bauhaus.cz"

    private(set) var token: String?
    private(set) var refreshToken: String?
    private(set) var name: String?
    private(set) var email: String?
    private(set) var customerID: Int?
    var lastError: String?

    var isLoggedIn: Bool { token != nil }

    private init() {
        token = Keychain.get("bauhaus.token")
        refreshToken = Keychain.get("bauhaus.refresh")
        let d = UserDefaults.standard
        name = d.string(forKey: "bauhaus.name")
        email = d.string(forKey: "bauhaus.email")
        customerID = d.object(forKey: "bauhaus.customerID") as? Int
    }

    // MARK: - přihlášení a odhlášení

    /// Token převzatý z přihlášení na webu Bauhausu (WKWebView v aplikaci).
    func adopt(token: String, refresh: String?, user: [String: Any]?) async {
        self.token = token
        self.refreshToken = refresh
        Keychain.set(token, "bauhaus.token")
        if let refresh { Keychain.set(refresh, "bauhaus.refresh") }
        if let user { apply(user) }
        await loadMe()
    }

    func logout() {
        token = nil; refreshToken = nil; name = nil; email = nil; customerID = nil
        Keychain.delete("bauhaus.token"); Keychain.delete("bauhaus.refresh")
        for k in ["bauhaus.name", "bauhaus.email", "bauhaus.customerID"] { UserDefaults.standard.removeObject(forKey: k) }
    }

    private func apply(_ user: [String: Any]) {
        let first = user["firstname"] as? String ?? ""
        let last = user["lastname"] as? String ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { name = full }
        if let e = user["email"] as? String { email = e }
        if let id = user["id"] as? Int { customerID = id } else if let s = user["id"] as? String, let id = Int(s) { customerID = id }
        let d = UserDefaults.standard
        d.set(name, forKey: "bauhaus.name"); d.set(email, forKey: "bauhaus.email"); d.set(customerID, forKey: "bauhaus.customerID")
    }

    func loadMe() async {
        guard let r = try? await authed({ t in try await Self.request("GET", "/api/user/me?token=\(t)") }),
              let user = r["result"] as? [String: Any] else { return }
        apply(user)
    }

    // MARK: - objednávky a rezervace

    struct Order: Identifiable, Hashable {
        struct Line: Hashable { let sku: String; let name: String; let qty: Double; let price: Double? }
        let id: String
        let number: String
        let date: String
        let status: String
        let total: Double?
        let lines: [Line]
        let reservation: Bool
        var store: String? = nil
    }

    func orders() async throws -> [Order] {
        let r = try await authed { t in try await Self.request("GET", "/api/user/order-history?token=\(t)&pageSize=50&currentPage=1") }
        let items = ((r["result"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        return items.compactMap { o in
            let lines: [Order.Line] = (o["items"] as? [[String: Any]] ?? []).compactMap { i in
                guard i["parent_item_id"] == nil || i["parent_item_id"] is NSNull, let sku = i["sku"] as? String else { return nil }
                return Order.Line(sku: sku, name: i["name"] as? String ?? sku,
                                  qty: Self.num(i["qty_ordered"]) ?? 1, price: Self.num(i["price_incl_tax"]) ?? Self.num(i["price"]))
            }
            let number = (o["increment_id"] as? String) ?? "\(o["entity_id"] ?? "")"
            return Order(id: "o" + number, number: number, date: String((o["created_at"] as? String ?? "").prefix(10)),
                         status: Self.statusText(o["status"] as? String), total: Self.num(o["grand_total"]),
                         lines: lines, reservation: false)
        }
    }

    func reservations() async throws -> [Order] {
        let r = try await authed { t in try await Self.request("GET", "/api/ext/vaimo-click-and-collect/reservations/mine/customerToken/\(t)") }
        let items = r["result"] as? [[String: Any]] ?? []
        return items.compactMap { o in
            let lines: [Order.Line] = (o["items"] as? [[String: Any]] ?? []).compactMap { i in
                guard let sku = (i["sku"] as? String) ?? (i["product_sku"] as? String) else { return nil }
                return Order.Line(sku: sku, name: (i["name"] as? String) ?? (i["product_name"] as? String) ?? sku,
                                  qty: Self.num(i["qty"]) ?? Self.num(i["qty_ordered"]) ?? 1,
                                  price: Self.num(i["price_incl_tax"]) ?? Self.num(i["price"]))
            }
            let number = (o["number"] as? String) ?? (o["increment_id"] as? String) ?? "\(o["reservation_id"] ?? "")"
            return Order(id: "r" + number, number: number,
                         date: String(((o["created_at"] as? String) ?? (o["date"] as? String) ?? "").prefix(10)),
                         status: Self.statusText(o["status"] as? String), total: Self.num(o["grand_total"]) ?? Self.num(o["total"]),
                         lines: lines, reservation: true, store: (o["store_code"] as? String) ?? (o["store"] as? String))
        }
    }

    private static func statusText(_ s: String?) -> String {
        switch (s ?? "").lowercased() {
        case "pending", "new": return "Přijatá"
        case "processing": return "Zpracovává se"
        case "complete", "completed", "picked_up", "collected": return "Vyřízená"
        case "canceled", "cancelled": return "Zrušená"
        case "closed": return "Uzavřená"
        case "ready", "ready_for_pickup": return "Připravená k vyzvednutí"
        case "": return ""
        default: return s ?? ""
        }
    }

    // MARK: - košík a rezervace z nákupního seznamu

    struct BulkResult { let url: URL; let failed: [String] }

    /// Vloží položky do košíku (přihlášeného účtu, nebo hosta) a vrátí odkaz na oficiální
    /// pokladnu kosik.bauhaus.cz, kde se objednávka dokončí.
    func cartHandoff(_ items: [(sku: String, qty: Double)]) async throws -> BulkResult {
        let t = token ?? ""
        let create = try await Self.request("POST", "/api/cart/create?token=\(t)", body: [:])
        guard let cart = create["result"] as? String ?? (create["result"] as? Int).map(String.init) else {
            throw AccountError.message(Self.errorText(create) ?? "Košík se nepodařilo založit.")
        }
        let res = try await Self.request("POST", "/api/ext/cart-bulk-actions/carts/items/bulk-add", body: [
            "payload": ["items": items.map { ["sku": $0.sku, "qty": $0.qty] }, "cartUid": cart],
            "customerToken": t,
        ])
        let failed = Self.failedItems(res)
        guard let url = URL(string: "\(Self.checkoutBase)/vue/cart/sync/token/\(t.isEmpty ? "none" : t)/cart/\(cart)") else {
            throw AccountError.message("Chybný odkaz na košík.")
        }
        return BulkResult(url: url, failed: failed)
    }

    /// Rezervace k vyzvednutí na prodejně: nastaví prodejnu, vloží položky do sekce Rezervace
    /// a vrátí odkaz na oficiální košík, kde se rezervace potvrdí.
    func reserveHandoff(_ items: [(sku: String, qty: Double)], store: String) async throws -> BulkResult {
        guard isLoggedIn else { throw AccountError.message("Rezervace potřebuje přihlášení k účtu Bauhaus.") }
        if customerID == nil { await loadMe() }
        guard let cid = customerID else { throw AccountError.message("Nepodařilo se načíst účet. Přihlas se znovu.") }
        _ = try? await authed { t in
            try await Self.request("PUT", "/api/ext/vaimo-storelocator/savestore-api/customer/me/updatesavedstore",
                                   body: ["payload": ["storeCode": store], "customerToken": t])
        }
        let res = try await authed { t in
            try await Self.request("POST", "/api/ext/cart-bulk-actions/reservations/items/bulk-add",
                                   body: ["payload": ["items": items.map { ["sku": $0.sku, "qty": $0.qty] }], "customerId": cid],
                                   bearer: t)
        }
        let failed = Self.failedItems(res)
        guard let t = token else { throw AccountError.message("Přihlášení vypršelo.") }
        let create = try await Self.request("POST", "/api/cart/create?token=\(t)", body: [:])
        let cart = create["result"] as? String ?? (create["result"] as? Int).map(String.init) ?? ""
        guard let url = URL(string: "\(Self.checkoutBase)/vue/cart/sync/token/\(t)/cart/\(cart)") else {
            throw AccountError.message("Chybný odkaz na košík.")
        }
        return BulkResult(url: url, failed: failed)
    }

    private static func failedItems(_ res: [String: Any]) -> [String] {
        (res["result"] as? [[String: Any]] ?? []).compactMap { r in
            let status = (r["status"] as? String ?? "").lowercased()
            guard status != "success" else { return nil }
            let name = r["product_name"] as? String ?? r["sku"] as? String ?? "?"
            if let a = num(r["available_qty"]), let q = num(r["requested_qty"]), a < q {
                return "\(name): k dispozici jen \(Int(a)) ks"
            }
            return "\(name): \(r["message"] as? String ?? "nejde přidat")"
        }
    }

    // MARK: - síť

    enum AccountError: LocalizedError {
        case message(String), expired
        var errorDescription: String? {
            switch self {
            case .message(let m): return m
            case .expired: return "Přihlášení k účtu Bauhaus vypršelo. Přihlas se znovu ve Více."
            }
        }
    }

    /// Volání s tokenem; když vypršel, jednou ho obnoví (stejně jako web).
    private func authed(_ call: (String) async throws -> [String: Any]) async throws -> [String: Any] {
        guard let t = token else { throw AccountError.expired }
        let r = try await call(t)
        if !Self.isAuthError(r) { return r }
        guard let rt = refreshToken,
              let fresh = try? await Self.request("POST", "/api/user/refresh", body: ["refreshToken": rt]),
              let nt = fresh["result"] as? String, (fresh["code"] as? Int) == 200 else {
            token = nil
            Keychain.delete("bauhaus.token")
            throw AccountError.expired
        }
        token = nt
        Keychain.set(nt, "bauhaus.token")
        let again = try await call(nt)
        if Self.isAuthError(again) { throw AccountError.expired }
        return again
    }

    private static func isAuthError(_ r: [String: Any]) -> Bool {
        if let c = r["code"] as? Int, c == 401 { return true }
        if let res = r["result"] as? [String: Any], let c = res["code"] as? Int, c == 401 { return true }
        let msg = (errorText(r) ?? "").lowercased()
        return msg.contains("isn't authorized") || msg.contains("not authorized") || msg.contains("token")
            && (msg.contains("expired") || msg.contains("invalid"))
    }

    private static func errorText(_ r: [String: Any]) -> String? {
        if let s = r["result"] as? String, (r["code"] as? Int ?? 200) != 200 { return s }
        if let res = r["result"] as? [String: Any] { return (res["errorMessage"] as? String) ?? (res["message"] as? String) }
        return r["message"] as? String
    }

    static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    static func request(_ method: String, _ path: String, body: [String: Any]? = nil, bearer: String? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: base) else { throw AccountError.message("Chybná adresa.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await session.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 { return ["code": 401] }
        return json
    }
}

/// Minimální obal Klíčenky (token účtu Bauhaus).
enum Keychain {
    static func set(_ value: String, _ key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecAttrService as String: "cz.ponk.bauhaus",
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                                kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecAttrService as String: "cz.ponk.bauhaus", kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecAttrService as String: "cz.ponk.bauhaus"]
        SecItemDelete(q as CFDictionary)
    }
}
