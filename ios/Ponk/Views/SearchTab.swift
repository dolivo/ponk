import SwiftUI

/// Záložka hledání (v iOS 26 samostatné skleněné tlačítko). Bez zadaného textu ukazuje kategorie.
struct SearchTab: View {
    /// Mění se při dalším klepnutí na Hledat v menu: vrátí se na začátek a otevře klávesnici.
    var focusTrigger = 0
    @Environment(AppModel.self) private var app
    @FocusState private var searchFocused: Bool
    @State private var searchShown = false
    @State private var showScanner = false
    @State private var path = NavigationPath()
    @State private var text = ""
    @State private var suggest: SuggestResponse?
    @AppStorage(Recents.searchesKey) private var recent = ""

    var body: some View {
        NavigationStack(path: $path) {
            CategoryBrowser(cat1: nil, cat2: nil)
                .searchable(text: $text, isPresented: $searchShown, prompt: "Hledat v nabídce Bauhausu")
                .searchFocused($searchFocused)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                            .accessibilityLabel("Skenovat čárový kód")
                    }
                }
                .searchSuggestions { suggestions }
                .onSubmit(of: .search) { submit(text) }
                .task(id: text) { await loadSuggestions() }
                .ponkDestinations()
        }
        .fullScreenCover(isPresented: $showScanner) { ScannerSheet() }
        .onChange(of: focusTrigger) {
            let wasDeep = !path.isEmpty
            path = NavigationPath()
            Task { @MainActor in
                // po návratu na začátek zásobníku, aby pole hledání bylo vidět
                try? await Task.sleep(for: .milliseconds(wasDeep ? 400 : 30))
                searchShown = true
                searchFocused = true
            }
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if text.isEmpty {
            ForEach(Recents.list(recent), id: \.self) { r in
                Button { submit(r) } label: {
                    Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(Color.ponkInk)
                }
            }
        } else if let s = suggest {
            if let c = s.corrected {
                Button { submit(c) } label: {
                    Label { Text("Myslel jsi \(Text(c).fontWeight(.heavy))?") } icon: { Image(systemName: "wand.and.sparkles") }
                        .foregroundStyle(Color.ponkInk)
                }
            }
            ForEach(s.categories) { c in
                Button { go(ResultsRoute(query: c.query, title: c.name)) } label: {
                    LabeledContent { Text("kategorie") } label: { Label(c.name, systemImage: "square.grid.2x2") }
                }
            }
            ForEach(s.brands, id: \.self) { b in
                Button { go(ResultsRoute(query: ["brand": b], title: b)) } label: {
                    LabeledContent { Text("značka") } label: { Label(b, systemImage: "tag") }
                }
            }
            ForEach(s.products) { p in
                Button { go(ProductRoute(sku: p.sku)) } label: {
                    HStack(spacing: 10) {
                        ProductImage(path: p.image, w: 80, h: 99).frame(width: 40, height: 40)
                        Text(p.name).lineLimit(2).foregroundStyle(Color.ponkInk)
                        Spacer()
                        Text("\(money(p.price)) Kč").font(.ponk(15, .heavy)).foregroundStyle(Color.ponkInk)
                    }
                }
            }
        }
    }

    private func submit(_ t: String) {
        let q = t.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        recent = Recents.adding(q, to: recent)
        go(ResultsRoute(query: ["q": q], title: "„\(q)“"))
    }

    private func go<R: Hashable>(_ route: R) {
        path.append(route)
    }

    private func loadSuggestions() async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { suggest = nil; return }
        try? await Task.sleep(for: .milliseconds(180)) // krátké zpoždění při psaní
        guard !Task.isCancelled else { return }
        suggest = try? await app.api.get("suggest", ["q": t], as: SuggestResponse.self)
    }
}

/// Procházení kategorií po úrovních; poslední úroveň otevře výsledky.
struct CategoryBrowser: View {
    let cat1: String?
    let cat2: String?
    @Environment(AppModel.self) private var app
    @State private var data: CategoriesResponse?
    @State private var deals: [Item] = []
    @State private var loadedFor = -2
    @State private var error: String?
    /// Naposledy procházená kategorie („Pokračuj, kde jsi skončil“): "cat1|cat2".
    @AppStorage("lastCategory") private var lastCategory = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNotice()
                if let data {
                    if cat1 == nil { home(data) } else { categoryPage(data) }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(60)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .ponkPage()
        .navigationTitle(cat2 ?? cat1 ?? "Kategorie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if cat1 != nil {
                // nadpis je velký v obsahu stránky; tady jen tlačítko na všechny produkty
                ToolbarItem(placement: .principal) { Text("") }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ResultsRoute(query: query, title: cat2 ?? cat1 ?? "")) {
                        Text("Všech \(money(Double(data?.total ?? 0)))")
                            .font(.ponk(15, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(Color.ponkRed, in: Capsule())
                    }
                    .opacity(data == nil ? 0 : 1)
                }
            }
        }
        .ponkBrandToolbar(cat1 == nil) // logo jen na první úrovni záložky Hledat
        .task(id: app.meta?.products ?? -1) {
            // návrat z detailu: obsah už je načtený pro stejná data
            if loadedFor == (app.meta?.products ?? -1), data != nil { return }
            await load()
            loadedFor = app.meta?.products ?? -1
        }
        .onAppear {
            if let cat1 { lastCategory = [cat1, cat2].compactMap { $0 }.joined(separator: "|") }
        }
    }

    private var query: Query {
        var q = Query()
        q["cat1"] = cat1
        q["cat2"] = cat2
        return q
    }

    // MARK: - úvod záložky Hledat

    /// Akční a sezónní výběry (Dušičky, Úklid sněhu…) se nemíchají mezi hlavní oddělení.
    private static let seasonal = ["vánoc", "velikono", "dušič", "halloween", "do školy", "jaro", "jarní", "léto", "letní",
                                   "podzim", "zim", "čarodějnic", "doprodej", "sezón", "sněh"]

    private func isSeasonal(_ name: String) -> Bool {
        let n = name.lowercased()
        return Self.seasonal.contains { n.contains($0) }
    }

    @ViewBuilder
    private func home(_ d: CategoriesResponse) -> some View {
        let main = d.values.filter { $0.count >= 300 && !isSeasonal($0.value) }
        let season = d.values.filter { isSeasonal($0.value) }.max { $0.count < $1.count }
        let extra = d.values.filter { c in !main.contains(c) && c != season }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let season {
                    NavigationLink(value: CategoryRoute(cat1: season.value, cat2: nil)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("TEĎ V SEZÓNĚ").font(.ponk(13, .semibold)).opacity(0.9)
                            Spacer(minLength: 8)
                            Text(season.value).font(.ponk(26, .heavy)).lineLimit(1)
                            Text("\(money(Double(season.count))) \(plural(season.count, "produkt", "produkty", "produktů"))")
                                .font(.ponk(14)).opacity(0.92)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(width: 240, height: 118, alignment: .leading)
                        .background(Color.ponkRed, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
                if let last = continueRoute {
                    NavigationLink(value: last.route) {
                        VStack(alignment: .leading, spacing: 0) {
                            Label("Pokračuj", systemImage: "clock").font(.ponk(13)).foregroundStyle(Color.ponkMuted)
                            Spacer(minLength: 8)
                            Text(last.title).font(.ponk(20, .heavy)).lineLimit(2).foregroundStyle(Color.ponkInk)
                            if let sub = last.subtitle {
                                Text(sub).font(.ponk(14)).foregroundStyle(Color.ponkMuted).lineLimit(1)
                            }
                        }
                        .padding(14)
                        .frame(width: 200, height: 118, alignment: .leading)
                        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .popIn()

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink { CalculatorsView() } label: { chip("Kalkulačky", "function") }
                NavigationLink { PlatformsView() } label: { chip("Moje aku", "battery.100percent.bolt") }
                NavigationLink(value: ResultsRoute(query: ["label": "gift", "sort": "discount"], title: "Dárky k nákupu")) {
                    chip("Dárky k nákupu", "gift")
                }
                NavigationLink(value: ResultsRoute(query: ["label": "sell_off", "sort": "discount"], title: "Výprodej")) {
                    chip("Výprodej", "tag")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }

        HStack(alignment: .firstTextBaseline) {
            Text("Kategorie").font(.ponk(21, .heavy))
            Spacer()
            Text("\(main.count) \(plural(main.count, "oddělení", "oddělení", "oddělení"))")
                .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(main) { c in
                NavigationLink(value: CategoryRoute(cat1: c.value, cat2: nil)) { tile(c) }
                    .buttonStyle(.plain)
                    .popIn()
            }
        }
        .padding(.horizontal, 16)

        if !extra.isEmpty {
            Text("Sezóna a akce").font(.ponk(21, .heavy)).padding(.horizontal, 16).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(extra) { c in
                        NavigationLink(value: CategoryRoute(cat1: c.value, cat2: nil)) {
                            HStack(spacing: 6) {
                                Text(c.value).font(.ponk(16, .semibold))
                                Text("\(c.count)").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                            }
                            .foregroundStyle(Color.ponkInk)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Color.ponkSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var continueRoute: (route: CategoryRoute, title: String, subtitle: String?)? {
        let parts = lastCategory.split(separator: "|").map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        if parts.count > 1 { return (CategoryRoute(cat1: first, cat2: parts[1]), parts[1], first) }
        return (CategoryRoute(cat1: first, cat2: nil), first, nil)
    }

    private func chip(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.ponk(16, .semibold))
            .foregroundStyle(Color.ponkInk)
            .symbolRenderingMode(.monochrome)
            .labelStyle(TintedIconLabel())
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.ponkSurface, in: Capsule())
    }

    private func tile(_ c: CategoryValue) -> some View {
        let style = CategoryStyle.of(c.value)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: style.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: 34, height: 34)
                    .background(style.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                Text(money(Double(c.count))).font(.ponk(13)).foregroundStyle(Color.ponkMuted)
            }
            Text(c.value).font(.ponk(17, .heavy)).foregroundStyle(Color.ponkInk)
                .lineLimit(2).multilineTextAlignment(.leading)
            if let subs = c.subs, !subs.isEmpty {
                Text(subs.joined(separator: " · ")).font(.ponk(13)).foregroundStyle(Color.ponkMuted)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - stránka kategorie

    @ViewBuilder
    private func categoryPage(_ d: CategoriesResponse) -> some View {
        Text(cat2 ?? cat1 ?? "")
            .font(.ponk(32, .heavy, relativeTo: .largeTitle))
            .foregroundStyle(Color.ponkInk)
            .padding(.horizontal, 16)

        if !deals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nejlepší slevy tady").font(.ponk(19, .heavy))
                    Spacer()
                    NavigationLink(value: ResultsRoute(query: query.merging(["disc": "1", "sort": "discount"]) { $1 },
                                                       title: "Slevy: \(cat2 ?? cat1 ?? "")")) {
                        Text("\(money(Double(d.discounted ?? 0))) ve slevě").font(.ponk(15, .semibold))
                    }
                    .tint(Color.ponkRedDeep)
                }
                .padding(.horizontal, 16)
                Rail(items: deals)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(cat2 == nil ? "Podkategorie" : "Druhy").font(.ponk(19, .heavy)).padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(d.values.enumerated()), id: \.element.id) { i, c in
                    link(for: c) { row(c, last: i == d.values.count - 1) }
                        .popIn()
                }
            }
            .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    private func row(_ c: CategoryValue, last: Bool) -> some View {
        HStack(spacing: 12) {
            ProductImage(path: c.image, w: 120, h: 149)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.value).font(.ponk(17, .semibold)).foregroundStyle(Color.ponkInk)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(([money(Double(c.count))] + (c.subs ?? [])).joined(separator: c.subs?.isEmpty == false ? " · " : ""))
                    .font(.ponk(13)).foregroundStyle(Color.ponkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ponkMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.ponkPage).frame(height: 1).padding(.leading, 72) }
        }
    }

    @ViewBuilder
    private func link<L: View>(for c: CategoryValue, @ViewBuilder label: () -> L) -> some View {
        if cat2 != nil {
            NavigationLink(value: ResultsRoute(query: query.merging(["cat3": c.value]) { $1 }, title: c.value)) { label() }
                .buttonStyle(.plain)
        } else if let cat1 {
            NavigationLink(value: CategoryRoute(cat1: cat1, cat2: c.value)) { label() }.buttonStyle(.plain)
        } else {
            NavigationLink(value: CategoryRoute(cat1: c.value, cat2: nil)) { label() }.buttonStyle(.plain)
        }
    }

    private func load() async {
        do {
            data = try await app.api.get("categories", query, as: CategoriesResponse.self)
            error = nil
            if cat1 != nil {
                // filtry tu nejsou potřeba (facets=0), jen prvních pár produktů
                let r = try? await app.api.get("search", query.merging(["disc": "1", "sort": "discount", "facets": "0"]) { $1 }, as: SearchResponse.self)
                deals = Array((r?.items ?? []).prefix(12))
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Ikona štítku v barvě Ponku, text v barvě písma.
private struct TintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.ponkRed).font(.system(size: 15, weight: .semibold))
            configuration.title
        }
    }
}

/// Ikona a barva oddělení podle názvu (Bauhaus kategorie ikony nemá).
enum CategoryStyle {
    static func of(_ name: String) -> (symbol: String, color: Color) {
        let n = name.lowercased()
        let table: [(String, String, Color)] = [
            ("zahrad", "leaf.fill", .ponkGreen),
            ("nářadí", "wrench.and.screwdriver.fill", .ponkRed),
            ("bydlení", "sofa.fill", Color(light: 0x7A4A1E, dark: 0xC79560)),
            ("svítidl", "lightbulb.fill", Color(light: 0xB07A00, dark: 0xF2C300)),
            ("koupeln", "shower.fill", Color(light: 0x1F6FB2, dark: 0x5DA8E8)),
            ("železář", "gearshape.2.fill", Color(light: 0x4A4D52, dark: 0xB8BBC0)),
            ("barvy", "paintbrush.pointed.fill", Color(light: 0x7A3FB2, dark: 0xB98AE8)),
            ("elektro", "powerplug.fill", Color(light: 0xD45A00, dark: 0xFF9440)),
            ("dveře", "door.left.hand.closed", Color(light: 0x7A4A1E, dark: 0xC79560)),
            ("stavebnin", "square.stack.3d.up.fill", Color(light: 0x4A4D52, dark: 0xB8BBC0)),
            ("podlah", "square.split.bottomrightquarter.fill", Color(light: 0x0F7C7A, dark: 0x4CC7C2)),
            ("vánoc", "snowflake", .ponkRed),
            ("úklid", "sparkles", Color(light: 0x0F7C7A, dark: 0x4CC7C2)),
            ("kuchyn", "fork.knife", Color(light: 0xD45A00, dark: 0xFF9440)),
            ("obklad", "square.grid.3x3.fill", Color(light: 0x0F7C7A, dark: 0x4CC7C2)),
            ("topení", "flame.fill", Color(light: 0xD45A00, dark: 0xFF9440)),
            ("auto", "car.fill", Color(light: 0x1F6FB2, dark: 0x5DA8E8)),
            ("camping", "tent.fill", .ponkGreen),
            ("regál", "archivebox.fill", Color(light: 0x4A4D52, dark: 0xB8BBC0)),
        ]
        for (key, symbol, color) in table where n.contains(key) { return (symbol, color) }
        return ("square.grid.2x2.fill", .ponkMuted)
    }
}
