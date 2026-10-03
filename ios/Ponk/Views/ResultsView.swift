import SwiftUI

let sortOptions: [(key: String, title: String)] = [
    ("relevance", "Doporučené"), ("price_asc", "Od nejlevnějšího"), ("price_desc", "Od nejdražšího"),
    ("discount", "Největší skutečná sleva"), ("drop", "Naposledy zlevněné"), ("unit", "Nejnižší cena za jednotku"),
    ("rating", "Nejlépe hodnocené"), ("newest", "Nejnovější v nabídce"), ("newest_seen", "Naposledy přidané"),
]

struct ResultsView: View {
    let route: ResultsRoute
    /// Katalog: hlavní stránka se všemi položkami, hledáním, rychlými filtry a čtečkou kódů.
    var catalog = false
    @Environment(AppModel.self) private var app
    @State private var query: Query
    @State private var result: SearchResponse?
    @State private var items: [Item] = []
    @State private var error: String?
    @State private var loadingMore = false
    @State private var showFilters = false
    @State private var showSort = false
    @State private var showSave = false
    @State private var showScanner = false
    @State private var text = ""
    @AppStorage("listMode") private var listMode = false

    init(route: ResultsRoute, catalog: Bool = false) {
        self.route = route
        self.catalog = catalog
        _query = State(initialValue: route.query)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                OfflineNotice()
                if let result {
                    Text("\(money(Double(result.total))) \(plural(result.total, "produkt", "produkty", "produktů"))")
                        .font(.ponk(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ponkMuted)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
                if catalog { QuickFilters(query: $query, filters: quickFilters) }
                ActiveChips(query: $query, hidden: Set(quickFilters.filter { $0.isOn(query) }.map(\.id)))
                if !items.isEmpty {
                    Shelf(items: items, list: listMode) { Task { await loadMore() } }
                    if loadingMore { ProgressView().frame(maxWidth: .infinity).padding(20) }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else if result != nil {
                    ContentUnavailableView("Nic neodpovídá filtrům", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Zkus některý filtr zrušit nebo hledat obecněji."))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(60)
                }
                Color.clear.frame(height: 70) // místo pro plovoucí tlačítka
            }
        }
        .ponkPage(bottomFade: 84)
        .navigationTitle(route.title)
        .ponkBrandToolbar(catalog)
        .toolbar {
            if catalog {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                        .accessibilityLabel("Načíst čárový kód")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { listMode.toggle() } label: {
                    Image(systemName: listMode ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(listMode ? "Zobrazit mřížku" : "Zobrazit seznam")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSave = true } label: { Image(systemName: "bell.badge") }
                    .accessibilityLabel("Hlídat toto hledání")
            }
        }
        .overlay(alignment: .bottom) { floatingBar }
        .sheet(isPresented: $showFilters) {
            FiltersSheet(query: $query, facets: result?.facets, total: result?.total ?? 0)
        }
        .sheet(isPresented: $showSort) {
            SortSheet(selection: Binding(get: { query["sort"] ?? "relevance" }, set: { query["sort"] = $0 }))
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSave) {
            SaveSearchSheet(query: query, suggestedName: route.title)
                .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $showScanner) {
            ScannerSheet { code in text = code }
        }
        .modifier(CatalogSearch(enabled: catalog, text: $text, query: $query))
        .task(id: query) { await load() }
        .refreshable { await load() }
        // fasety (počty pro filtry) se počítají, až když je opravdu potřeba
        .onChange(of: showFilters) { _, open in
            if open, result?.facets == nil { Task { await loadFacets() } }
        }
        .onChange(of: app.meta?.products) { _, _ in Task { await load() } }
        .task {
            if let id = route.savedID { try? await app.api.send("DELETE", "saved/\(id)/seen") }
        }
    }

    /// Plovoucí skleněná tlačítka Filtry a Řazení nad spodní lištou (jako Allegro/Alza).
    private var floatingBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { showFilters = true } label: {
                    Label(filterCount > 0 ? "Filtry (\(filterCount))" : "Filtry", systemImage: "line.3.horizontal.decrease")
                        .font(.ponk(16, .semibold))
                        .padding(.horizontal, 4)
                }
                .ponkGlassButton()
                Button { showSort = true } label: {
                    Label(sortOptions.first { $0.key == (query["sort"] ?? "relevance") }?.title ?? "Řazení",
                          systemImage: "arrow.up.arrow.down")
                        .font(.ponk(16, .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .ponkGlassButton()
            }
            .controlSize(.large)
        }
        .padding(.bottom, 10)
    }

    private var filterCount: Int {
        query.keys.filter { !["q", "sort", "cat1", "page"].contains($0) }.count
    }

    private var quickFilters: [QuickFilter] {
        guard catalog else { return [] }
        let store = app.myStore ?? "888"
        return [
            .multi(id: "labelsell_off", title: "Výprodej", key: "label", value: "sell_off"),
            .single(id: "store", title: "Skladem: \(app.storeName(store))", key: "store", value: store),
            .single(id: "online", title: "Skladem online", key: "online", value: "1"),
            .single(id: "disc", title: "Sleva 30 %+", key: "disc", value: "30"),
            .single(id: "drop", title: "Zlevněno za 7 dní", key: "drop_days", value: "7"),
        ]
    }

    private func load() async {
        error = nil
        do {
            var q = query
            // Fasety jsou nejdražší část hledání – bez otevřených filtrů je nepotřebujeme.
            if !showFilters { q["facets"] = "0" }
            let r = try await app.api.get("search", q, as: SearchResponse.self)
            guard !Task.isCancelled else { return } // mezitím se změnil dotaz
            result = r
            items = r.items
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }

    /// Doplní jen fasety; načtené stránky výsledků zůstanou.
    private func loadFacets() async {
        guard let r = try? await app.api.get("search", query, as: SearchResponse.self) else { return }
        let current = result
        result = SearchResponse(total: r.total, page: current?.page ?? r.page, pages: current?.pages ?? r.pages,
                                items: [], facets: r.facets)
        if current == nil { items = r.items }
    }

    private func loadMore() async {
        guard let r = result, r.page < r.pages, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        var q = query
        q["page"] = String(r.page + 1)
        q["facets"] = "0"
        if let next = try? await app.api.get("search", q, as: SearchResponse.self) {
            items += next.items
            result = SearchResponse(total: next.total, page: next.page, pages: next.pages, items: [], facets: result?.facets ?? r.facets)
        }
    }
}

/// Aktivní filtry jako "čipy" – klepnutím se filtr zruší.
struct ActiveChips: View {
    @Binding var query: Query
    /// Čipy, které už ukazují rychlé filtry nahoře.
    var hidden: Set<String> = []
    @Environment(AppModel.self) private var app

    private struct Chip: Identifiable {
        let id: String
        let title: String
        let remove: (inout Query) -> Void
    }

    private var chips: [Chip] {
        var out: [Chip] = []
        func multi(_ key: String, _ title: (String) -> String) {
            for v in (query[key] ?? "").split(separator: "|").map(String.init) {
                out.append(Chip(id: key + v, title: title(v)) { q in
                    let rest = (q[key] ?? "").split(separator: "|").map(String.init).filter { $0 != v }
                    q[key] = rest.isEmpty ? nil : rest.joined(separator: "|")
                })
            }
        }
        if let c = query["cat3"] { out.append(Chip(id: "cat3", title: c) { $0["cat3"] = nil }) }
        else if let c = query["cat2"] { out.append(Chip(id: "cat2", title: c) { $0["cat2"] = nil; $0["cat3"] = nil }) }
        else if let c = query["cat1"] { out.append(Chip(id: "cat1", title: c) { $0["cat1"] = nil; $0["cat2"] = nil; $0["cat3"] = nil }) }
        multi("brand") { $0 }
        if query["pmin"] != nil || query["pmax"] != nil {
            out.append(Chip(id: "price", title: "\(query["pmin"] ?? "0")–\(query["pmax"] ?? "∞") Kč") { $0["pmin"] = nil; $0["pmax"] = nil })
        }
        if let d = query["disc"] { out.append(Chip(id: "disc", title: "Sleva \(d) %+") { $0["disc"] = nil }) }
        multi("label") { app.labelName($0) }
        if let s = query["store"] { out.append(Chip(id: "store", title: "Skladem: \(app.storeName(s))") { $0["store"] = nil }) }
        if query["online"] != nil { out.append(Chip(id: "online", title: "Skladem online") { $0["online"] = nil }) }
        if let d = query["drop_days"], let n = Int(d) {
            out.append(Chip(id: "drop", title: "Zlevněno za \(n) \(plural(n, "den", "dny", "dní"))") { $0["drop_days"] = nil })
        }
        if let d = query["restock_days"], let n = Int(d) {
            out.append(Chip(id: "restock", title: n == 1 ? "Naskladněno od včera" : "Naskladněno za \(n) \(plural(n, "den", "dny", "dní"))") { $0["restock_days"] = nil })
        }
        if let d = query["new_days"], let n = Int(d) {
            out.append(Chip(id: "new", title: "Nové za \(n) \(plural(n, "den", "dny", "dní"))") { $0["new_days"] = nil })
        }
        if let r = query["rating"] { out.append(Chip(id: "rating", title: "Hodnocení \(r)+") { $0["rating"] = nil }) }
        if query["unit"] != nil { out.append(Chip(id: "unit", title: "S cenou za jednotku") { $0["unit"] = nil }) }
        for key in query.keys.sorted() where key.hasPrefix("a_") { multi(key) { $0 } }
        return out.filter { !hidden.contains($0.id) }
    }

    var body: some View {
        let list = chips
        if !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { chip in
                        Button {
                            chip.remove(&query)
                        } label: {
                            HStack(spacing: 6) {
                                Text(chip.title)
                                Image(systemName: "xmark").font(.caption2.bold())
                            }
                            .font(.ponk(15, .semibold, relativeTo: .subheadline))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(Color.ponkSurface)
                            .background(Color.ponkInk, in: Capsule())
                        }
                        .accessibilityLabel("Zrušit filtr \(chip.title)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }
}

/// Rychlý filtr v katalogu: jedno klepnutí zapne, druhé vypne.
struct QuickFilter: Identifiable {
    let id: String
    let title: String
    let isOn: (Query) -> Bool
    let toggle: (inout Query) -> Void

    static func single(id: String, title: String, key: String, value: String) -> QuickFilter {
        QuickFilter(id: id, title: title,
                    isOn: { $0[key] == value },
                    toggle: { q in q[key] = q[key] == value ? nil : value })
    }

    /// Hodnota v seznamu odděleném „|“ (např. štítky).
    static func multi(id: String, title: String, key: String, value: String) -> QuickFilter {
        func values(_ q: Query) -> [String] { (q[key] ?? "").split(separator: "|").map(String.init) }
        return QuickFilter(id: id, title: title,
                           isOn: { values($0).contains(value) },
                           toggle: { q in
                               var v = values(q)
                               if let i = v.firstIndex(of: value) { v.remove(at: i) } else { v.append(value) }
                               q[key] = v.isEmpty ? nil : v.joined(separator: "|")
                           })
    }
}

struct QuickFilters: View {
    @Binding var query: Query
    let filters: [QuickFilter]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters) { f in
                    let on = f.isOn(query)
                    Button { f.toggle(&query) } label: {
                        HStack(spacing: 5) {
                            if on { Image(systemName: "checkmark").font(.caption.bold()) }
                            Text(f.title)
                        }
                        .font(.ponk(15, .semibold, relativeTo: .subheadline))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.ponkSurface : Color.ponkInk)
                        .background(on ? Color.ponkInk : Color.ponkSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Color.ponkLine))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: filters.map { $0.isOn(query) })
    }
}

/// Hledání v katalogu: píše se rovnou do dotazu (s krátkou pauzou), nabízí poslední hledání.
private struct CatalogSearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    @Binding var query: Query
    @AppStorage(Recents.searchesKey) private var recent = ""

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Hledat ve všech položkách")
                .searchSuggestions {
                    if text.isEmpty {
                        ForEach(Recents.list(recent), id: \.self) { s in
                            Label(s, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(Color.ponkInk)
                                .searchCompletion(s)
                        }
                    }
                }
                .onSubmit(of: .search) {
                    recent = Recents.adding(text, to: recent)
                    apply(text)
                }
                .task(id: text) {
                    // krátká pauza při psaní, ať se nehledá po každém písmenu
                    if !text.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                    guard !Task.isCancelled else { return }
                    apply(text)
                }
        } else {
            content
        }
    }

    private func apply(_ t: String) {
        let q = t.trimmingCharacters(in: .whitespaces)
        let value: String? = q.isEmpty ? nil : q
        if query["q"] != value { query["q"] = value }
    }
}

struct SortSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sortOptions, id: \.key) { option in
                Button {
                    selection = option.key
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title).font(.ponk(17)).foregroundStyle(Color.ponkInk)
                        Spacer()
                        if option.key == selection { Image(systemName: "checkmark").foregroundStyle(Color.ponkRed) }
                    }
                }
            }
            .navigationTitle("Řazení")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SaveSearchSheet: View {
    let query: Query
    let suggestedName: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Název", text: $name).font(.ponk(18))
                } footer: {
                    Text(error ?? "Po každé denní kontrole uvidíš v sekci Hlídané, kolik nových nebo zlevněných produktů odpovídá tomuto hledání.")
                }
            }
            .navigationTitle("Hlídat hledání")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit hledání") { Task { await save() } }
                }
            }
            .onAppear { name = suggestedName.replacingOccurrences(of: "„", with: "").replacingOccurrences(of: "“", with: "") }
        }
    }

    private func save() async {
        let q = query.filter { !["page", "sort", "facets"].contains($0.key) }
        do {
            try await app.api.send("POST", "saved", body: ["name": name.isEmpty ? suggestedName : name, "query": q])
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
