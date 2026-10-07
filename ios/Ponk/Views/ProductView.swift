import Charts
import SwiftUI
import UIKit

struct ProductView: View {
    let sku: String
    @Environment(AppModel.self) private var app
    @State private var p: ProductDetail?
    @State private var error: String?
    @State private var refreshing = false
    @State private var showWatch = false
    @State private var watchTick = 0

    var body: some View {
        ScrollView {
            if let p {
                content(p)
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(80)
            }
        }
        .ponkPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("Aktualizovat cenu a sklad teď")
                .disabled(refreshing)
            }
            if let p {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { copy(p.name) } label: { Label("Kopírovat název", systemImage: "textformat") }
                        Button { copy(p.sku) } label: { Label("Kopírovat kód \(p.sku)", systemImage: "number") }
                        if let ean = p.ean, !ean.isEmpty {
                            Button { copy(ean) } label: { Label("Kopírovat EAN", systemImage: "barcode") }
                        }
                        if let d = p.description, !d.isEmpty {
                            Button { copy(plainText(fromHTML: d)) } label: { Label("Kopírovat popis", systemImage: "text.alignleft") }
                        }
                        if !p.params.isEmpty {
                            Button { copy(p.params.map { "\($0.label): \($0.value)" }.joined(separator: "\n")) } label: {
                                Label("Kopírovat parametry", systemImage: "list.bullet.rectangle")
                            }
                        }
                        Button { copy(summary(p)) } label: { Label("Kopírovat vše", systemImage: "doc.on.doc") }
                        if let url = productURL(p) {
                            Button { copy(url.absoluteString) } label: { Label("Kopírovat odkaz", systemImage: "link") }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Kopírovat")
                }
            }
            if let p, let url = productURL(p) {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) }
            }
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: watchTick)
        .sensoryFeedback(.success, trigger: copyTick)
        .overlay(alignment: .top) {
            if let copied {
                Label(copied, systemImage: "checkmark.circle.fill")
                    .font(.ponk(15, .semibold, relativeTo: .footnote))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .ponkGlassCapsule(tint: Color.ponkGreen.opacity(0.25))
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showWatch) {
            if let p {
                WatchSheet(product: p) { watchTick += 1; Task { await load() } }
                    .presentationDetents([.height(300)])
            }
        }
    }

    @ViewBuilder
    private func content(_ p: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            OfflineNotice()
            Gallery(pictures: p.pictures)

            VStack(alignment: .leading, spacing: 6) {
                if !p.cat_path.isEmpty {
                    Text(p.cat_path.joined(separator: " / "))
                        .font(.ponk(14, relativeTo: .footnote))
                        .foregroundStyle(Color.ponkMuted)
                }
                Text(p.name)
                    .font(.ponk(27, .heavy, relativeTo: .title))
                    .foregroundStyle(Color.ponkInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button { copy(p.name) } label: { Label("Kopírovat název", systemImage: "doc.on.doc") }
                        Button { copy(summary(p)) } label: { Label("Kopírovat vše", systemImage: "doc.on.doc.fill") }
                    }
                Stars(rating: p.rating, count: p.rating_count, size: 15)
                Text([p.brand, "kód \(p.sku)", p.ean.map { "EAN \($0)" }, p.dims].compactMap { $0 }.joined(separator: ", "))
                    .font(.ponk(14, relativeTo: .footnote))
                    .foregroundStyle(Color.ponkMuted)
                    .textSelection(.enabled) // kód a EAN jde podržením zkopírovat
            }
            .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                if p.active == 0 {
                    Label("Tento produkt už Bauhaus nenabízí\(p.last_price.map { " (naposledy \(money($0)) Kč)" } ?? "").", systemImage: "xmark.circle")
                        .font(.ponk(15, .semibold))
                        .foregroundStyle(Color.ponkRedDeep)
                }
                PriceTag(price: p.price, discount: p.real_discount, big: true)
                if let d = p.real_discount, d > 0, let min30 = p.min30_price {
                    Text("O \(Text("\(d) %").foregroundStyle(Color.ponkRedDeep).fontWeight(.heavy)) levnější než nejnižší cena za posledních 30 dní (\(money(min30)) Kč).")
                        .font(.ponk(16))
                }
                if let was = p.was_price {
                    Text("Původně \(Text("\(money(was)) Kč").strikethrough())").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                }
                if let unit = p.unit_price, let u = p.unit {
                    Text("\(money2(unit)) Kč/\(u)").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                }
                Text(changeText(p)).font(.ponk(14)).foregroundStyle(Color.ponkMuted)
            }
            .padding(.horizontal, 14)

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    if p.watch != nil {
                        Button {
                            Task { await unwatch(p) }
                        } label: {
                            Label("Přestat hlídat", systemImage: "eye.slash").font(.ponk(16, .semibold))
                        }
                        .ponkGlassButton()
                    } else {
                        Button {
                            showWatch = true
                        } label: {
                            Label("Hlídat cenu", systemImage: "eye").font(.ponk(16, .heavy))
                        }
                        .ponkProminentButton()
                    }
                    if let url = URL(string: "https://www.bauhaus.cz/\(p.url_path ?? "")") {
                        Link(destination: url) {
                            Label("Na bauhaus.cz", systemImage: "arrow.up.right.square").font(.ponk(16, .semibold))
                        }
                        .ponkGlassButton()
                    }
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 14)

            if let w = p.watch {
                Text(watchText(w))
                    .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                    .padding(.horizontal, 14)
            }

            if !p.usps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.usps, id: \.self) { u in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Rectangle().fill(Color.ponkRed).frame(width: 8, height: 8)
                            Text(u).font(.ponk(16))
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            Block(title: "Kde je skladem") { StockList(p: p) }
            Block(title: "Vývoj ceny") { PriceChart(history: p.history, current: p.price) }
            Block(title: "Hodnocení zákazníků") { ReviewsSection(sku: p.sku) }

            if !p.params.isEmpty {
                Block(title: "Parametry") {
                    VStack(spacing: 0) {
                        ForEach(p.params) { param in
                            HStack(alignment: .top) {
                                Text(param.label).foregroundStyle(Color.ponkMuted).frame(maxWidth: .infinity, alignment: .leading)
                                Text(param.value).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.ponk(15))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button { copy(param.value) } label: { Label("Kopírovat hodnotu", systemImage: "doc.on.doc") }
                                Button { copy("\(param.label): \(param.value)") } label: { Label("Kopírovat řádek", systemImage: "text.alignleft") }
                            }
                            .overlay(alignment: .top) { Rectangle().fill(Color.ponkLine).frame(height: 1) }
                        }
                    }
                }
            }

            if let d = p.description, !d.isEmpty {
                Block(title: "Popis") {
                    Text(plainText(fromHTML: d)).font(.ponk(16)).lineSpacing(3)
                        .textSelection(.enabled) // podržením jde označit a zkopírovat libovolná část
                }
            }
        }
        .padding(.bottom, 30)
    }

    private func watchText(_ w: WatchInfo) -> String {
        var text = "Hlídáš od \(shortDay(w.added)) (tehdy \(money(w.added_price)) Kč)"
        if let t = w.target { text += ", cílová cena \(money(t)) Kč" }
        return text + "."
    }

    private func changeText(_ p: ProductDetail) -> String {
        if let prev = p.prev_price, let price = p.price, let at = p.price_changed_at {
            return "\(price < prev ? "Zlevněno" : "Zdraženo") \(shortDay(at)) z \(money(prev)) Kč."
        }
        return "Cena se nezměnila od \(shortDay(p.first_seen)), kdy ji Ponk začal sledovat."
    }

    @State private var copyTick = 0
    @State private var copied: String?

    private func productURL(_ p: ProductDetail) -> URL? {
        URL(string: "https://www.bauhaus.cz/\(p.url_path ?? "")")
    }

    /// Název, kód, cena a odkaz – hodí se do zprávy nebo poznámek.
    private func summary(_ p: ProductDetail) -> String {
        var lines = [p.name, "Kód: \(p.sku)" + (p.ean.map { ", EAN \($0)" } ?? "")]
        if let price = p.price { lines.append("Cena: \(money(price)) Kč") }
        if let url = productURL(p) { lines.append(url.absoluteString) }
        return lines.joined(separator: "\n")
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copyTick += 1
        let tick = copyTick
        withAnimation(.snappy) { copied = "Zkopírováno" }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if tick == copyTick { withAnimation(.snappy) { copied = nil } }
        }
    }

    private func load(refresh: Bool = false) async {
        if refresh { refreshing = true }
        defer { refreshing = false }
        do {
            p = try await app.api.get("product/\(sku)", refresh ? ["refresh": "1"] : [:], as: ProductDetail.self)
            error = nil
            Recents.addViewed(sku)
        } catch is CancellationError {
        } catch {
            if p == nil { self.error = error.localizedDescription }
        }
    }

    private func unwatch(_ p: ProductDetail) async {
        try? await app.api.send("DELETE", "watch/\(p.sku)")
        watchTick += 1
        await load()
        await app.loadMeta()
    }
}

private struct Block<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.ponk(20, .heavy, relativeTo: .title3)).foregroundStyle(Color.ponkInk)
            content()
        }
        .padding(.horizontal, 14)
    }
}

private struct Gallery: View {
    let pictures: [String]
    @State private var page = 0
    @State private var zoom = false

    var body: some View {
        if pictures.isEmpty {
            Color.white.frame(height: 280).overlay { Image(systemName: "photo").foregroundStyle(.gray) }
        } else {
            TabView(selection: $page) {
                ForEach(Array(pictures.enumerated()), id: \.offset) { i, path in
                    ProductImage(path: path, w: 600, h: 744).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pictures.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 360)
            .background(Color.white)
            .contentShape(Rectangle())
            .onTapGesture { zoom = true }
            .accessibilityAction(named: "Zobrazit fotky na celou obrazovku") { zoom = true }
            .fullScreenCover(isPresented: $zoom) { ZoomGallery(pictures: pictures, page: $page) }
        }
    }
}

private struct StockList: View {
    let p: ProductDetail
    @Environment(AppModel.self) private var app

    var body: some View {
        let my = app.myStore
        let stores = (app.meta?.stores ?? []).sorted { a, b in
            if a.code == my { return true }
            if b.code == my { return false }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
        VStack(spacing: 0) {
            row(name: "E-shop", qty: p.online_in_stock == 1 ? p.online_qty : nil, position: nil, mine: false)
            ForEach(stores) { s in
                row(name: s.name, qty: p.stock[s.code], position: p.positions[s.code], mine: s.code == my, store: s.code)
            }
        }
        .background(Color.ponkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ponkLine))
        .sheet(item: $mapFor) { req in StoreMapSheet(request: req) }
    }

    @State private var mapFor: MapRequest?

    private func row(name: String, qty: Double?, position: Position?, mine: Bool, store: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.ponk(16, .semibold))
                Spacer()
                if let qty, qty > 0 {
                    Text("\(money(qty)) ks").font(.ponk(16, .heavy)).monospacedDigit()
                } else {
                    Text("není").font(.ponk(16)).foregroundStyle(Color.ponkMuted)
                }
            }
            if let qty, qty > 0, let pos = position, let shelf = pos.shelf {
                // Regál a pole, kde zboží v prodejně leží – jako regálová visačka.
                HStack(spacing: 6) {
                    Text("Regál \(shelf), pole \(pos.field ?? "–")").fontWeight(.semibold)
                    if let zone = pos.zone, !zone.isEmpty, zone.range(of: "^R\\d+\\s+F\\d+", options: .regularExpression) == nil {
                        Text(zone).opacity(0.75)
                    }
                }
                .font(.ponk(14, relativeTo: .footnote))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(Color.ponkLabelInk)
                .background(Color.ponkLabel, in: RoundedRectangle(cornerRadius: 2))
                if let store {
                    Button {
                        mapFor = MapRequest(store: store, storeName: name, shelf: shelf, field: pos.field)
                    } label: {
                        Label("Ukázat na mapě prodejny", systemImage: "map")
                            .font(.ponk(15, .semibold, relativeTo: .footnote))
                    }
                    .buttonStyle(.borderless)
                    .tint(Color.ponkRedDeep)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(mine ? Color.ponkSurface2 : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Color.ponkLine).frame(height: 1) }
    }
}

struct PriceChart: View {
    let history: [PricePoint]
    let current: Double?

    private struct Point: Identifiable {
        let date: Date
        let price: Double
        var id: Date { date }
    }

    var body: some View {
        var points = history.compactMap { h in dayDate(h.day).map { Point(date: $0, price: h.price) } }
        if let current, let last = points.last, last.date < Calendar.current.startOfDay(for: Date()) {
            points.append(Point(date: Date(), price: current))
        }
        let prices = points.map(\.price)
        let lo = (prices.min() ?? 0) * 0.9
        let hi = (prices.max() ?? 1) * 1.05

        return Group {
            if history.count < 2 {
                Text("Ponk zatím zná jen dnešní cenu. Každá další denní kontrola přidá bod a uvidíš, jak se cena vyvíjí.")
                    .font(.ponk(15)).foregroundStyle(Color.ponkMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Chart(points) { pt in
                        AreaMark(x: .value("Den", pt.date), yStart: .value("Min", lo), yEnd: .value("Cena", pt.price))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(Color.ponkInk.opacity(0.07))
                        LineMark(x: .value("Den", pt.date), y: .value("Cena", pt.price))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(Color.ponkInk)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                    .chartYScale(domain: lo...max(hi, lo + 1))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
                    .frame(height: 180)
                    Text("Nejníže \(money(prices.min())) Kč, nejvýš \(money(prices.max())) Kč za dobu sledování.")
                        .font(.ponk(13, relativeTo: .caption)).foregroundStyle(Color.ponkMuted)
                }
            }
        }
    }
}

struct WatchSheet: View {
    let product: ProductDetail
    var onSaved: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("např. \(money((product.price ?? 0) * 0.8))", text: $target)
                            .keyboardType(.numberPad)
                            .font(.ponk(20, .semibold))
                        Text("Kč").foregroundStyle(Color.ponkMuted)
                    }
                } header: {
                    Text("Upozornit, až cena klesne na")
                } footer: {
                    Text(error ?? "Nepovinné. Zlevnění uvidíš v sekci Hlídané a na úvodní obrazovce.")
                }
            }
            .navigationTitle("Hlídat cenu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hlídat cenu") { Task { await save() } }
                }
            }
        }
    }

    private func save() async {
        let digits = target.filter(\.isNumber)
        do {
            let target: Any = Int(digits).map { $0 as Any } ?? NSNull()
            try await app.api.send("POST", "watch", body: ["sku": product.sku, "target": target])
            await app.loadMeta()
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Recenze zákazníků načtené živě z Bauhausu (včetně přeložených ze zahraničních webů BAUHAUS).
private struct ReviewsSection: View {
    let sku: String
    @State private var page: ReviewsPage?
    @State private var failed = false
    @State private var loadingMore = false

    var body: some View {
        Group {
            if let page {
                if page.count == 0 && page.items.isEmpty {
                    Text("Zatím bez recenzí. Hodnocení se sbírá ze všech webů BAUHAUS (Česko, Německo, Rakousko…).")
                        .font(.ponk(15)).foregroundStyle(Color.ponkMuted)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(page)
                        ForEach(page.items) { ReviewCard(review: $0) }
                        if page.next != nil {
                            Button {
                                Task { await more() }
                            } label: {
                                if loadingMore { ProgressView() } else {
                                    Text("Další recenze (\(max(0, page.total - page.items.count)))").font(.ponk(16, .semibold))
                                }
                            }
                            .ponkGlassButton()
                            .disabled(loadingMore)
                        }
                    }
                }
            } else if failed {
                HStack {
                    Text("Recenze se nepodařilo načíst.").font(.ponk(15)).foregroundStyle(Color.ponkMuted)
                    Spacer()
                    Button("Zkusit znovu") { Task { await load() } }.font(.ponk(15, .semibold))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(12)
            }
        }
        .task(id: sku) { await load() }
    }

    private func summary(_ page: ReviewsPage) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 4) {
                Text(page.average.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "cs_CZ"))))
                    .font(.ponk(40, .heavy, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ponkInk)
                Stars(rating: Int((page.average * 20).rounded()), count: page.count, size: 13, showText: false)
                Text("\(page.count) \(plural(page.count, "hodnocení", "hodnocení", "hodnocení"))")
                    .font(.ponk(13)).foregroundStyle(Color.ponkMuted)
            }
            VStack(spacing: 3) {
                ForEach(Array(page.distribution.enumerated()), id: \.offset) { i, n in
                    HStack(spacing: 6) {
                        Text("\(5 - i)").font(.ponk(13, .semibold)).monospacedDigit().frame(width: 10)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ponkLine)
                                Capsule().fill(Color.ponkStar)
                                    .frame(width: page.count > 0 ? g.size.width * CGFloat(n) / CGFloat(page.count) : 0)
                            }
                        }
                        .frame(height: 6)
                        Text("\(n)").font(.ponk(13)).monospacedDigit().foregroundStyle(Color.ponkMuted).frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        failed = false
        do {
            page = try await ReviewsAPI.load(sku: sku)
        } catch is CancellationError {
        } catch {
            if page == nil { failed = true }
        }
    }

    private func more() async {
        guard let current = page, let next = current.next else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let more = try? await ReviewsAPI.load(sku: sku, cursor: next) {
            var merged = current
            let known = Set(current.items.map(\.id))
            merged.items += more.items.filter { !known.contains($0.id) }
            merged.next = more.next
            page = merged
        }
    }
}

private struct ReviewCard: View {
    let review: Review
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Stars(rating: review.rating * 20, count: nil, size: 12, showText: false)
                if !review.title.isEmpty {
                    Text(review.title).font(.ponk(16, .semibold)).foregroundStyle(Color.ponkInk).lineLimit(2)
                }
            }
            Text(showOriginal ? (review.original ?? review.text) : review.text)
                .font(.ponk(15))
                .foregroundStyle(Color.ponkInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text([review.author, dayDate(review.date)?.formatted(.dateTime.day().month(.defaultDigits).year().locale(Locale(identifier: "cs_CZ"))), review.verified ? "ověřený nákup" : nil]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                if review.recommended { Image(systemName: "hand.thumbsup.fill").foregroundStyle(Color.ponkGreen) }
            }
            .font(.ponk(13))
            .foregroundStyle(Color.ponkMuted)
            if review.original != nil {
                Button {
                    showOriginal.toggle()
                } label: {
                    Text(showOriginal ? "Zobrazit překlad"
                         : "Přeloženo\(review.country.isEmpty ? "" : " · \(review.country)")\(review.source.isEmpty ? "" : " (\(review.source))") · originál")
                        .font(.ponk(13, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ponkRedDeep)
            }
            ForEach(review.replies, id: \.self) { reply in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Odpověď BAUHAUS").font(.ponk(13, .semibold))
                    Text(reply).font(.ponk(14))
                }
                .foregroundStyle(Color.ponkInk)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ponkSurface2, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 6))
    }
}
