import SwiftUI

/// Záložka hledání (v iOS 26 samostatné skleněné tlačítko). Bez zadaného textu ukazuje kategorie.
struct SearchTab: View {
    @Environment(AppModel.self) private var app
    @State private var path = NavigationPath()
    @State private var text = ""
    @State private var suggest: SuggestResponse?
    @AppStorage(Recents.searchesKey) private var recent = ""

    var body: some View {
        NavigationStack(path: $path) {
            CategoryBrowser(cat1: nil, cat2: nil)
                .searchable(text: $text, prompt: "Hledat v nabídce Bauhausu")
                .searchSuggestions { suggestions }
                .onSubmit(of: .search) { submit(text) }
                .task(id: text) { await loadSuggestions() }
                .ponkDestinations()
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
    @State private var error: String?

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNotice()
                if cat1 != nil {
                    NavigationLink(value: ResultsRoute(query: query, title: cat2 ?? cat1 ?? "")) {
                        Label("Zobrazit všechny produkty", systemImage: "square.grid.2x2").font(.ponk(16, .semibold))
                    }
                    .ponkGlassButton()
                    .padding(.horizontal, 14)
                }
                if let data {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(data.values) { c in
                            link(for: c)
                        }
                    }
                    .padding(.vertical, 1)
                    .background(Color.ponkShelf)
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(60)
                }
            }
            .padding(.bottom, 20)
        }
        .ponkPage()
        .navigationTitle(cat2 ?? cat1 ?? "Kategorie")
        .ponkBrandToolbar(cat1 == nil) // logo jen na první úrovni záložky Hledat
        .task(id: app.meta?.products ?? -1) { await load() }
    }

    private var query: Query {
        var q = Query()
        q["cat1"] = cat1
        q["cat2"] = cat2
        return q
    }

    @ViewBuilder
    private func link(for c: CategoryValue) -> some View {
        if cat2 != nil {
            NavigationLink(value: ResultsRoute(query: query.merging(["cat3": c.value]) { $1 }, title: c.value)) { cell(c) }
                .buttonStyle(.plain)
        } else if let cat1 {
            NavigationLink(value: CategoryRoute(cat1: cat1, cat2: c.value)) { cell(c) }.buttonStyle(.plain)
        } else {
            NavigationLink(value: CategoryRoute(cat1: c.value, cat2: nil)) { cell(c) }.buttonStyle(.plain)
        }
    }

    private func cell(_ c: CategoryValue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(path: c.image, w: 240, h: 298)
            Text(c.value).font(.ponk(16, .semibold)).foregroundStyle(Color.ponkInk)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(money(Double(c.count))) \(plural(c.count, "produkt", "produkty", "produktů"))")
                .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.ponkSurface)
    }

    private func load() async {
        do {
            data = try await app.api.get("categories", query, as: CategoriesResponse.self)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
