import SwiftUI

/// Produkty k porovnání (nejvýš 3), uložené v telefonu jako „sku|sku|sku“.
enum Compare {
    static let key = "compare"
    static let max = 3

    static func list(_ raw: String) -> [String] { raw.split(separator: "|").map(String.init) }

    /// Přidá nebo odebere produkt; při čtvrtém vypadne nejstarší.
    static func toggled(_ sku: String, in raw: String) -> String {
        var l = list(raw)
        if let i = l.firstIndex(of: sku) { l.remove(at: i) } else { l.append(sku) }
        if l.count > max { l.removeFirst(l.count - max) }
        return l.joined(separator: "|")
    }
}

/// Porovnání 2–3 produktů vedle sebe: cena, cena za jednotku, hodnocení, sklad, platforma
/// a všechny parametry. Řádky, ve kterých se produkty liší, jsou zvýrazněné; jde nechat jen rozdíly.
struct CompareView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Compare.key) private var compare = ""
    @State private var products: [ProductDetail] = []
    @State private var onlyDiff = false
    @State private var loading = true

    private struct Row: Identifiable {
        let label: String
        let values: [String]
        var best: Int? = nil  // index nejlepší hodnoty (nejnižší cena…)
        var id: String { label }
        var differs: Bool { Set(values).count > 1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if products.count < 2 && !loading {
                    ContentUnavailableView("Přidej aspoň 2 produkty", systemImage: "square.split.2x1",
                                           description: Text("V detailu produktu klepni na ikonu porovnání, nebo podrž dlaždici a zvol Porovnat."))
                        .padding(.top, 40)
                }
                if !products.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Toggle("Jen rozdíly", isOn: $onlyDiff.animation(.snappy))
                            .font(.ponk(16, .semibold))
                            .tint(Color.ponkRed)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        ForEach(rows.filter { !onlyDiff || $0.differs }) { row($0) }
                    }
                    .padding(.bottom, 30)
                }
                if loading { ProgressView().padding(40) }
            }
            .ponkPage()
            .navigationTitle("Porovnání")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Vyprázdnit", role: .destructive) { compare = ""; products = [] }
                        .disabled(products.isEmpty)
                }
            }
            .ponkDestinations()
        }
        .task(id: compare) { await load() }
    }

    // MARK: - hlavička: fotka, název, cena, odebrání

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(products, id: \.sku) { p in
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: ProductRoute(sku: p.sku)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ProductImage(path: p.image, w: 300, h: 372)
                                .aspectRatio(300.0 / 372.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(p.name).font(.ponk(14, .semibold)).lineLimit(3)
                                .foregroundStyle(Color.ponkInk)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    PriceTag(price: p.price, discount: p.real_discount)
                    Button(role: .destructive) {
                        withAnimation(.snappy) { compare = Compare.toggled(p.sku, in: compare) }
                    } label: {
                        Label("Odebrat", systemImage: "xmark.circle").font(.ponk(13, .semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Color.ponkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - řádky

    private func row(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if r.differs { Circle().fill(Color.ponkRed).frame(width: 6, height: 6) }
                Text(r.label).font(.ponk(13, .semibold)).foregroundStyle(Color.ponkMuted)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(r.values.enumerated()), id: \.offset) { i, v in
                    Text(v.isEmpty ? "–" : v)
                        .font(.ponk(15, r.best == i ? .heavy : (r.differs ? .semibold : .regular)))
                        .foregroundStyle(r.best == i ? Color.ponkGreen : Color.ponkInk)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(r.differs ? Color.ponkRed.opacity(0.05) : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Color.ponkLine).frame(height: 1) }
    }

    private var rows: [Row] {
        guard !products.isEmpty else { return [] }
        let store = app.myStore
        var out: [Row] = []
        func lowest(_ xs: [Double?]) -> Int? {
            let vals = xs.compactMap { $0 }
            guard vals.count > 1, Set(vals).count > 1, let m = vals.min() else { return nil }
            return xs.firstIndex { $0 == m }
        }
        func highest(_ xs: [Double?]) -> Int? {
            let vals = xs.compactMap { $0 }
            guard vals.count > 1, Set(vals).count > 1, let m = vals.max() else { return nil }
            return xs.firstIndex { $0 == m }
        }
        let prices = products.map(\.price)
        out.append(Row(label: "Cena", values: prices.map { $0.map { "\(money($0)) Kč" } ?? "" }, best: lowest(prices)))
        let min30 = products.map(\.min30_price)
        if min30.contains(where: { $0 != nil }) {
            out.append(Row(label: "Nejnižší cena za 30 dní", values: min30.map { $0.map { "\(money($0)) Kč" } ?? "" }))
        }
        let units = products.map(\.unit_price)
        if units.contains(where: { $0 != nil }) {
            out.append(Row(label: "Cena za jednotku",
                           values: products.map { p in p.unit_price.map { "\(money2($0)) Kč/\(p.unit ?? "")" } ?? "" },
                           best: Set(products.compactMap(\.unit)).count == 1 ? lowest(units) : nil))
        }
        let ratings = products.map { $0.rating.map { Double($0) / 20 } }
        if ratings.contains(where: { $0 != nil }) {
            out.append(Row(label: "Hodnocení",
                           values: products.map { p in
                               guard let r = p.rating else { return "" }
                               let stars = String(format: "%.1f", Double(r) / 20).replacingOccurrences(of: ".", with: ",")
                               return p.rating_count.map { "\(stars) ★ (\($0))" } ?? "\(stars) ★"
                           }, best: highest(ratings)))
        }
        if let store {
            let q = products.map { $0.stock[store] }
            out.append(Row(label: "Skladem: \(app.storeName(store))",
                           values: q.map { $0.map { $0 > 0 ? "\(money($0)) ks" : "není" } ?? "není" }, best: highest(q)))
        }
        if products.contains(where: { $0.brand != nil }) {
            out.append(Row(label: "Značka", values: products.map { $0.brand ?? "" }))
        }
        if products.contains(where: { $0.platform != nil }) {
            out.append(Row(label: "Aku platforma", values: products.map { p in
                guard let pl = p.platform else { return "" }
                return pl.title + (pl.body == 1 ? " (bez aku)" : pl.body == 0 ? " (s aku)" : "")
            }))
        }
        if products.contains(where: { $0.warranty != nil }) {
            out.append(Row(label: "Záruka BAUHAUS", values: products.map { $0.warranty ?? "" }))
        }
        if products.contains(where: { $0.dims != nil }) {
            out.append(Row(label: "Rozměry", values: products.map { $0.dims ?? "" }))
        }
        // parametry: pořadí podle prvního produktu, pak ostatní
        var labels: [String] = []
        for p in products { for prm in p.params where !labels.contains(prm.label) { labels.append(prm.label) } }
        for label in labels {
            let values = products.map { p in p.params.first { $0.label == label }?.value ?? "" }
            out.append(Row(label: label, values: values))
        }
        return out
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var loaded: [ProductDetail] = []
        for sku in Compare.list(compare) {
            if let p = try? await app.api.get("product/\(sku)", as: ProductDetail.self) { loaded.append(p) }
        }
        withAnimation(.snappy) { products = loaded }
    }
}
