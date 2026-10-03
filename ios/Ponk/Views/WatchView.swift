import SwiftUI

struct WatchView: View {
    @Environment(AppModel.self) private var app
    @State private var items: [Item] = []
    @State private var saved: [SavedSearch] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            OfflineNotice()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section {
                if items.isEmpty, loaded {
                    Text("Zatím nic nehlídáš. V detailu produktu klepni na Hlídat cenu.")
                        .font(.ponk(15)).foregroundStyle(Color.ponkMuted)
                }
                ForEach(items) { item in
                    NavigationLink(value: ProductRoute(sku: item.sku)) {
                        ProductRow(item: displayItem(item)).padding(.horizontal, -14)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowBackground(Color.ponkSurface)
                    .swipeActions {
                        Button("Přestat hlídat", role: .destructive) { Task { await unwatch(item) } }
                    }
                }
            } header: {
                Text("Produkty").font(.ponk(20, .heavy, relativeTo: .title3)).foregroundStyle(Color.ponkInk).textCase(nil)
            }

            Section {
                if saved.isEmpty, loaded {
                    Text("Žádná uložená hledání. Ve výsledcích klepni na zvonek a hledání se bude hlídat.")
                        .font(.ponk(15)).foregroundStyle(Color.ponkMuted)
                }
                ForEach(saved) { s in
                    NavigationLink(value: ResultsRoute(query: s.query.values, title: s.name, savedID: s.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.ponk(17, .semibold))
                                Text("\(money(Double(s.total))) \(plural(s.total, "produkt", "produkty", "produktů"))")
                                    .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                            }
                            Spacer()
                            if s.fresh > 0 {
                                Text("\(s.fresh) \(plural(s.fresh, "novinka", "novinky", "novinek"))")
                                    .font(.ponk(13, .heavy))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .foregroundStyle(.white)
                                    .background(Color.ponkRed, in: Capsule())
                            }
                        }
                    }
                    .swipeActions {
                        Button("Smazat", role: .destructive) { Task { await delete(s) } }
                    }
                }
            } header: {
                Text("Hledání").font(.ponk(20, .heavy, relativeTo: .title3)).foregroundStyle(Color.ponkInk).textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ponkPage()
        .navigationTitle("Hlídané")
        .ponkBrandToolbar()
        .overlay {
            if let error, !loaded { ErrorState(message: error) { Task { await load() } } }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    /// U hlídaných ukazujeme změnu od chvíle, kdy se začaly hlídat.
    private func displayItem(_ i: Item) -> Item {
        guard let added = i.added_price, let price = i.price, abs(added - price) >= 0.5 else { return i }
        return Item(sku: i.sku, name: i.name, brand: i.brand, image: i.image, price: i.price, was_price: i.was_price,
                    min30_price: i.min30_price, real_discount: i.real_discount, labels: i.labels,
                    online_in_stock: i.online_in_stock, unit_price: i.unit_price, unit: i.unit, rating: i.rating,
                    prev_price: added, price_changed_at: i.price_changed_at ?? i.added, drop_pct: i.drop_pct,
                    cat3: i.cat3, dims: i.dims, store_qty: i.store_qty, added: i.added, added_price: i.added_price,
                    target: i.target, active: i.active, last_price: i.last_price, rating_count: i.rating_count)
    }

    private func load() async {
        do {
            items = try await app.api.get("watch", as: ListResponse<Item>.self).items
            saved = try await app.api.get("saved", as: ListResponse<SavedSearch>.self).items
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func unwatch(_ item: Item) async {
        try? await app.api.send("DELETE", "watch/\(item.sku)")
        await load()
        await app.loadMeta()
    }

    private func delete(_ s: SavedSearch) async {
        try? await app.api.send("DELETE", "saved/\(s.id)")
        await load()
    }
}
