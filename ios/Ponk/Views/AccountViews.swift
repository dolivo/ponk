import SafariServices
import SwiftUI
import WebKit

// MARK: - přihlášení přes oficiální stránku Bauhausu

/// Přihlášení probíhá přímo na webu bauhaus.cz uvnitř aplikace (i přes Google/Facebook).
/// Ponk heslo nevidí: po přihlášení si z webu převezme jen přihlašovací token.
struct BauhausLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var done = false
    var onLogin: () -> Void = {}

    var body: some View {
        NavigationStack {
            BauhausLoginWeb { token, refresh, user in
                guard !done else { return }
                done = true
                Task {
                    await BauhausAccount.shared.adopt(token: token, refresh: refresh, user: user)
                    onLogin()
                    dismiss()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Přihlas se na stránce Bauhausu. Ponk si převezme jen přihlášení, heslo nevidí.")
                    .font(.ponk(14))
                    .foregroundStyle(Color.ponkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.ponkPage)
            }
            .navigationTitle("Účet BAUHAUS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } }
            }
        }
    }
}

private struct BauhausLoginWeb: UIViewRepresentable {
    var onToken: (String, String?, [String: Any]?) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: URL(string: "https://www.bauhaus.cz/my-account")!))
        context.coordinator.start(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.stop() }

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    @MainActor
    final class Coordinator {
        let onToken: (String, String?, [String: Any]?) -> Void
        private var timer: Timer?
        private weak var web: WKWebView?

        init(onToken: @escaping (String, String?, [String: Any]?) -> Void) { self.onToken = onToken }

        func start(_ web: WKWebView) {
            self.web = web
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        }

        func stop() { timer?.invalidate(); timer = nil }

        /// Web ukládá přihlášení do localStorage (localForage „shop/user/…“).
        private func poll() {
            let js = """
            (function(){try{return JSON.stringify({t:localStorage.getItem('shop/user/current-token'),
            r:localStorage.getItem('shop/user/current-refresh-token'),u:localStorage.getItem('shop/user/current-user')})}catch(e){return null}})()
            """
            web?.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let s = result as? String,
                      let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return }
                func unwrap(_ v: Any?) -> String? {
                    guard let raw = v as? String, !raw.isEmpty, raw != "null" else { return nil }
                    if let d = raw.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String {
                        return parsed
                    }
                    return raw
                }
                guard let token = unwrap(obj["t"]), token.count > 10 else { return }
                var user: [String: Any]?
                if let u = obj["u"] as? String, let d = u.data(using: .utf8) {
                    user = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                }
                self.stop()
                self.onToken(token, unwrap(obj["r"]), user)
            }
        }
    }
}

// MARK: - oficiální pokladna v Safari

/// Pokladna kosik.bauhaus.cz v Safari uvnitř aplikace (automatické vyplňování, platba kartou).
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - účet ve Více

struct AccountSection: View {
    @State private var account = BauhausAccount.shared
    @State private var showLogin = false

    var body: some View {
        Section {
            if account.isLoggedIn {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? "Přihlášen").font(.ponk(17, .semibold))
                    if let e = account.email { Text(e).font(.ponk(14)).foregroundStyle(Color.ponkMuted) }
                }
                NavigationLink { OrdersView() } label: { Label("Moje objednávky a rezervace", systemImage: "shippingbox") }
                Button(role: .destructive) { account.logout() } label: { Label("Odhlásit", systemImage: "rectangle.portrait.and.arrow.right") }
            } else {
                Button { showLogin = true } label: { Label("Přihlásit se k účtu BAUHAUS", systemImage: "person.crop.circle") }
            }
        } header: {
            Text("Účet BAUHAUS")
        } footer: {
            Text("Přihlášení probíhá na stránce Bauhausu, Ponk heslo nevidí a přihlášení drží jen v Klíčence telefonu. Pak uvidíš objednávky a rezervace a nákupní seznam půjde rezervovat na prodejně.")
        }
        .sheet(isPresented: $showLogin) { BauhausLoginSheet() }
    }
}

// MARK: - objednávky a rezervace

struct OrdersView: View {
    @Environment(AppModel.self) private var app
    @State private var orders: [BauhausAccount.Order] = []
    @State private var loading = true
    @State private var error: String?
    @State private var images: [String: Item] = [:]
    @State private var showLogin = false

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).foregroundStyle(Color.ponkRedDeep)
                    if !BauhausAccount.shared.isLoggedIn {
                        Button("Přihlásit znovu") { showLogin = true }
                    }
                }
            }
            if orders.isEmpty, !loading, error == nil {
                Text("Zatím žádné objednávky ani rezervace.").foregroundStyle(Color.ponkMuted)
            }
            ForEach(orders) { o in
                Section {
                    ForEach(o.lines, id: \.self) { l in
                        NavigationLink(value: ProductRoute(sku: l.sku)) {
                            HStack(spacing: 10) {
                                ProductImage(path: images[l.sku]?.image, w: 80, h: 99).frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.name).font(.ponk(15)).lineLimit(2)
                                    Text("\(qtyText(l.qty)) ks" + (l.price.map { " · \(money($0)) Kč" } ?? ""))
                                        .font(.ponk(13)).foregroundStyle(Color.ponkMuted)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label(o.reservation ? "Rezervace \(o.number)" : "Objednávka \(o.number)",
                              systemImage: o.reservation ? "storefront" : "shippingbox")
                        Spacer()
                        Text(shortDay(o.date) + " " + String(o.date.prefix(4)))
                    }
                    .font(.ponk(14, .semibold)).textCase(nil)
                } footer: {
                    HStack {
                        Text(o.status)
                        if let s = o.store { Text("· \(app.storeName(s))") }
                        Spacer()
                        if let t = o.total { Text("\(money(t)) Kč").fontWeight(.heavy) }
                    }
                    .font(.ponk(13))
                }
            }
        }
        .navigationTitle("Objednávky")
        .ponkDestinations()
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showLogin, onDismiss: { Task { await load() } }) { BauhausLoginSheet() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let o = BauhausAccount.shared.orders()
            async let r = BauhausAccount.shared.reservations()
            let all = (try await o) + ((try? await r) ?? [])
            orders = all.sorted { $0.date > $1.date }
            error = nil
            await PurchaseSync.save(all, api: app.api)
            let skus = Array(Set(all.flatMap { $0.lines.map(\.sku) })).prefix(50)
            let items = (try? await app.api.get("items", ["skus": skus.joined(separator: "|")], as: ListResponse<Item>.self).items) ?? []
            images = Dictionary(items.map { ($0.sku, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Uloží koupené produkty do telefonu (pro „Koupeno 12. 10.“ v detailu produktu).
enum PurchaseSync {
    static func save(_ orders: [BauhausAccount.Order], api: PonkAPI) async {
        var rows: [[String: Any]] = []
        for o in orders where o.status != "Zrušená" {
            for l in o.lines {
                rows.append(["sku": l.sku, "day": o.date, "kind": o.reservation ? "reservation" : "order", "ref": o.number, "qty": l.qty])
            }
        }
        try? await api.send("POST", "purchases", body: ["items": rows])
    }

    /// Po spuštění aplikace: když je účet přihlášený, tiše obnoví seznam koupených produktů.
    @MainActor
    static func refresh(api: PonkAPI) async {
        guard BauhausAccount.shared.isLoggedIn else { return }
        let o = (try? await BauhausAccount.shared.orders()) ?? []
        let r = (try? await BauhausAccount.shared.reservations()) ?? []
        if !o.isEmpty || !r.isEmpty { await save(o + r, api: api) }
    }
}
