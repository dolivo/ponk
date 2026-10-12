import SwiftUI
import UIKit

/// Záložka „Seznam“: nákupní seznamy a hlídané produkty.
struct MyStuffView: View {
    @AppStorage("myStuffSection") private var section = 0

    var body: some View {
        Group {
            if section == 0 { ShoppingListView() } else { WatchView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Zobrazit", selection: $section) {
                Text("Nákupní seznam").tag(0)
                Text("Hlídané").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.ponkPage.opacity(0.94))
        }
    }
}

/// Nákupní seznam: položky seřazené podle regálů na zvolené prodejně (trasa prodejnou),
/// sklad, cena celkem, odškrtávání v obchodě, mapa trasy a sdílení.
struct ShoppingListView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("currentList") private var currentID = 0
    @AppStorage("listSortByShelf") private var sortByShelf = true
    @State private var lists: [ShoppingListInfo] = []
    @State private var detail: ShoppingListDetail?
    @State private var shelves: [String: BauhausLive.Shelf] = [:]
    @State private var liveStock: [String: [String: Double]] = [:]
    @State private var liveFor = ""
    @State private var error: String?
    @State private var prompt: Prompt?
    @State private var promptText = ""
    @State private var showMap = false
    @State private var confirmDelete = false
    @State private var tick = 0

    enum Prompt: Identifiable {
        case newList, rename, addText, note(ListEntry)
        var id: String {
            switch self {
            case .newList: return "new"
            case .rename: return "rename"
            case .addText: return "text"
            case .note(let e): return "note\(e.id)"
            }
        }
    }

    var body: some View {
        List {
            if let d = detail {
                header(d)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                if d.items.isEmpty {
                    ContentUnavailableView {
                        Label("Seznam je prázdný", systemImage: "checklist")
                    } description: {
                        Text("V detailu produktu klepni na Do seznamu, nebo přidej vlastní položku tlačítkem +.")
                    } actions: {
                        Button("Přidat vlastní položku") { ask(.addText) }.ponkGlassButton()
                    }
                    .listRowBackground(Color.clear)
                }
                let pending = routeOrder(d.items.filter { !$0.isChecked })
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { e in row(e, store: d.store) }
                    } header: {
                        sectionHeader(sortByShelf && !shelves.isEmpty ? "Nakoupit, po cestě prodejnou" : "Nakoupit")
                    }
                }
                let done = d.items.filter(\.isChecked)
                if !done.isEmpty {
                    Section {
                        ForEach(done) { e in row(e, store: d.store) }
                    } header: {
                        HStack {
                            sectionHeader("V košíku")
                            Spacer()
                            Button("Smazat") { Task { await clear("checked") } }
                                .font(.ponk(15, .semibold))
                                .foregroundStyle(Color.ponkRedDeep)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ponkPage()
        .navigationTitle(detail?.name ?? "Nákupní seznam")
        .ponkBrandToolbar()
        .toolbar { toolbar }
        .refreshable { await load(live: true) }
        .task { await load() }
        .onChange(of: currentID) { _, _ in Task { await load() } }
        .sensoryFeedback(.selection, trigger: tick)
        .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField(promptPlaceholder, text: $promptText)
            Button("Zrušit", role: .cancel) { prompt = nil }
            Button("Uložit") { Task { await submitPrompt() } }
        }
        .confirmationDialog("Smazat seznam „\(detail?.name ?? "")“?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Smazat seznam", role: .destructive) { Task { await deleteList() } }
        }
        .sheet(isPresented: $showMap) {
            if let d = detail {
                ListMapSheet(store: d.store, storeName: app.storeName(d.store), stops: stops(d))
            }
        }
    }

    // MARK: - hlavička se souhrnem

    @ViewBuilder
    private func header(_ d: ShoppingListDetail) -> some View {
        let storeName = app.storeName(d.store)
        let mine = d.stores.first { $0.code == d.store }?.have ?? 0
        let best = d.stores.max { $0.have < $1.have }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(money(d.open_total) + " Kč")
                        .font(.ponk(30, .heavy, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(Color.ponkInk)
                    Text("\(d.pending) \(plural(d.pending, "položka", "položky", "položek")) k nákupu"
                         + (d.total > d.open_total ? ", celkem se zakoupenými \(money(d.total)) Kč" : ""))
                        .font(.ponk(14, relativeTo: .footnote))
                        .foregroundStyle(Color.ponkMuted)
                }
                Spacer()
            }
            if d.pending > 0, !d.stores.isEmpty {
                Label {
                    Text("\(storeName): skladem \(mine) z \(d.pending)")
                } icon: {
                    Image(systemName: mine == d.pending ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                }
                .font(.ponk(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(mine == d.pending ? Color.ponkGreen : Color.ponkRedDeep)
                if let best, best.have > mine, best.code != d.store {
                    Button {
                        Task { await setStore(best.code) }
                    } label: {
                        Text("\(best.name) má skladem \(best.have) z \(d.pending). Nakupovat tam?")
                            .font(.ponk(14, relativeTo: .footnote))
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.borderless)
                    .tint(Color.ponkRedDeep)
                }
            }
            if d.pending > 0 {
                GlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { showMap = true } label: {
                            Label("Trasa na mapě", systemImage: "map").font(.ponk(15, .semibold))
                        }
                        .ponkGlassButton()
                        .disabled(stops(d).isEmpty)
                        ShareLink(item: shareText(d)) {
                            Label("Sdílet", systemImage: "square.and.arrow.up").font(.ponk(15, .semibold))
                        }
                        .ponkGlassButton()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.ponk(17, .heavy, relativeTo: .headline)).foregroundStyle(Color.ponkInk).textCase(nil)
    }

    // MARK: - řádek položky

    @ViewBuilder
    private func row(_ e: ListEntry, store: String) -> some View {
        let content = ListRow(entry: e, shelf: e.sku.flatMap { shelves[$0] }, stock: stockQty(e, store: store),
                              onToggle: { Task { await toggle(e) } },
                              onQty: { q in Task { await setQty(e, q) } })
        Group {
            if let sku = e.sku {
                NavigationLink(value: ProductRoute(sku: sku)) { content }
            } else {
                content
            }
        }
        .listRowBackground(Color.ponkSurface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await remove(e) } } label: { Label("Smazat", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { Task { await toggle(e) } } label: {
                Label(e.isChecked ? "Vrátit" : "V košíku", systemImage: e.isChecked ? "arrow.uturn.backward" : "cart")
            }
            .tint(Color.ponkGreen)
        }
        .contextMenu {
            Button { ask(.note(e)) } label: { Label(e.note == nil ? "Přidat poznámku" : "Upravit poznámku", systemImage: "note.text") }
            Button { UIPasteboard.general.string = e.title } label: { Label("Kopírovat název", systemImage: "doc.on.doc") }
            Button(role: .destructive) { Task { await remove(e) } } label: { Label("Smazat", systemImage: "trash") }
        }
    }

    private func stockQty(_ e: ListEntry, store: String) -> Double? {
        guard let sku = e.sku else { return nil }
        return liveStock[sku]?[store] ?? e.product?.store_qty
    }

    /// Po cestě prodejnou: podle čísla regálu a pole; vlastní položky a neznámé regály na konec.
    private func routeOrder(_ items: [ListEntry]) -> [ListEntry] {
        guard sortByShelf else { return items }
        func key(_ e: ListEntry) -> (Int, Int, Int) {
            guard let sku = e.sku, let s = shelves[sku] else { return (Int.max, 0, e.id) }
            return (s.number, Int(s.field) ?? 0, e.id)
        }
        return items.sorted { key($0) < key($1) }
    }

    private func stops(_ d: ShoppingListDetail) -> [ListMapSheet.Stop] {
        routeOrder(d.items.filter { !$0.isChecked }).compactMap { e in
            guard let sku = e.sku, let s = shelves[sku] else { return nil }
            return ListMapSheet.Stop(shelf: s.shelf, field: s.field, title: e.title)
        }
    }

    // MARK: - lišta

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { ask(.addText) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Přidat vlastní položku")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Seznamy") {
                    ForEach(lists) { l in
                        Button { currentID = l.id } label: {
                            if l.id == detail?.id {
                                Label("\(l.name) (\(l.open))", systemImage: "checkmark")
                            } else {
                                Text("\(l.name) (\(l.open))")
                            }
                        }
                    }
                    Button { ask(.newList) } label: { Label("Nový seznam", systemImage: "plus.rectangle.on.rectangle") }
                }
                Section("Prodejna") {
                    Picker("Prodejna", selection: Binding(get: { detail?.store ?? "" }, set: { v in Task { await setStore(v) } })) {
                        ForEach(app.meta?.stores ?? []) { Text($0.name).tag($0.code) }
                    }
                }
                Section {
                    Toggle(isOn: $sortByShelf) { Label("Řadit po cestě prodejnou", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    Button { Task { await clear("uncheck") } } label: { Label("Vrátit vše z košíku", systemImage: "arrow.uturn.backward") }
                    Button { Task { await clear("checked") } } label: { Label("Smazat zakoupené", systemImage: "cart.badge.minus") }
                    Button { ask(.rename) } label: { Label("Přejmenovat seznam", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Smazat seznam", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Možnosti seznamu")
        }
    }

    // MARK: - dialogy

    private func ask(_ p: Prompt) {
        switch p {
        case .rename: promptText = detail?.name ?? ""
        case .note(let e): promptText = e.note ?? ""
        default: promptText = ""
        }
        prompt = p
    }

    private var promptTitle: String {
        switch prompt {
        case .newList: return "Nový seznam"
        case .rename: return "Přejmenovat seznam"
        case .addText: return "Vlastní položka"
        case .note: return "Poznámka"
        case nil: return ""
        }
    }

    private var promptPlaceholder: String {
        switch prompt {
        case .newList, .rename: return "Např. Dřevník"
        case .addText: return "Např. lepicí páska"
        default: return "Např. barva odstín 1015"
        }
    }

    private func submitPrompt() async {
        let text = promptText.trimmingCharacters(in: .whitespaces)
        let p = prompt
        prompt = nil
        switch p {
        case .newList:
            try? await app.api.send("POST", "lists", body: ["name": text])
            if let l = try? await app.api.get("lists", as: ListResponse<ShoppingListInfo>.self).items.last { currentID = l.id }
        case .rename:
            if let d = detail, !text.isEmpty { try? await app.api.send("POST", "lists/\(d.id)", body: ["name": text]) }
        case .addText:
            if let d = detail, !text.isEmpty { try? await app.api.send("POST", "list/\(d.id)", body: ["text": text, "qty": 1]) }
        case .note(let e):
            try? await app.api.send("POST", "listitem/\(e.id)", body: ["note": text])
        case nil: break
        }
        await load()
    }

    // MARK: - data

    private func load(live: Bool = false) async {
        do {
            lists = try await app.api.get("lists", as: ListResponse<ShoppingListInfo>.self).items
            if !lists.contains(where: { $0.id == currentID }), let first = lists.first { currentID = first.id }
            let d = try await app.api.get("list/\(currentID)", as: ShoppingListDetail.self)
            detail = d
            error = nil
            await loadLive(d, force: live)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Regály a aktuální sklad živě z Bauhausu (offline zůstanou data ze stažené databáze).
    private func loadLive(_ d: ShoppingListDetail, force: Bool) async {
        let skus = d.items.compactMap(\.sku)
        let key = d.store + ":" + skus.sorted().joined(separator: ",")
        guard force || key != liveFor else { return }
        let r = await BauhausLive.shelves(skus: skus, store: d.store)
        if !r.shelves.isEmpty || !r.stock.isEmpty {
            shelves = r.shelves
            liveStock = r.stock
            liveFor = key
        }
    }

    private func toggle(_ e: ListEntry) async {
        if let i = detail?.items.firstIndex(where: { $0.id == e.id }) {
            withAnimation(.snappy) { detail?.items[i].checked = e.isChecked ? 0 : 1 }
        }
        tick += 1
        try? await app.api.send("POST", "listitem/\(e.id)", body: ["checked": !e.isChecked])
        await load()
    }

    private func setQty(_ e: ListEntry, _ q: Double) async {
        if let i = detail?.items.firstIndex(where: { $0.id == e.id }), q > 0 { detail?.items[i].qty = q }
        tick += 1
        try? await app.api.send("POST", "listitem/\(e.id)", body: ["qty": q])
        await load()
    }

    private func remove(_ e: ListEntry) async {
        try? await app.api.send("DELETE", "listitem/\(e.id)")
        await load()
    }

    private func clear(_ mode: String) async {
        guard let d = detail else { return }
        try? await app.api.send("POST", "list/\(d.id)", body: ["clear": mode])
        await load()
    }

    private func setStore(_ code: String) async {
        guard let d = detail else { return }
        try? await app.api.send("POST", "lists/\(d.id)", body: ["store": code])
        await load()
    }

    private func deleteList() async {
        guard let d = detail else { return }
        try? await app.api.send("DELETE", "lists/\(d.id)")
        currentID = 0
        await load()
    }

    /// Text pro sdílení: položky v pořadí po cestě prodejnou, regál, cena, součet.
    private func shareText(_ d: ShoppingListDetail) -> String {
        var lines = ["\(d.name) – \(app.storeName(d.store))", ""]
        for e in routeOrder(d.items.filter { !$0.isChecked }) {
            var line = "☐ \(qtyText(e.qty))× \(e.title)"
            if let sku = e.sku, let s = shelves[sku] { line += " (regál \(s.shelf)" + (s.field.isEmpty || s.field == "0" ? ")" : ", pole \(s.field))") }
            if let t = e.lineTotal { line += ", \(money(t)) Kč" }
            if let n = e.note { line += " – \(n)" }
            lines.append(line)
        }
        lines += ["", "Celkem: \(money(d.open_total)) Kč"]
        return lines.joined(separator: "\n")
    }
}

func qtyText(_ q: Double) -> String {
    q.rounded() == q ? String(Int(q)) : String(format: "%.1f", q).replacingOccurrences(of: ".", with: ",")
}

/// Řádek seznamu: zaškrtnutí, fotka, název, regál, sklad, množství a cena.
private struct ListRow: View {
    let entry: ListEntry
    let shelf: BauhausLive.Shelf?
    let stock: Double?
    let onToggle: () -> Void
    let onQty: (Double) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(entry.isChecked ? Color.ponkGreen : Color.ponkMuted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.isChecked ? "Vrátit z košíku" : "Dát do košíku")

            if let p = entry.product {
                ProductImage(path: p.image, w: 200, h: 248)
                    .frame(width: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .opacity(entry.isChecked ? 0.5 : 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.ponk(15, .semibold))
                    .foregroundStyle(entry.isChecked ? Color.ponkMuted : Color.ponkInk)
                    .strikethrough(entry.isChecked)
                    .lineLimit(2)
                if !entry.isChecked { badges }
                if let n = entry.note {
                    Text(n).font(.ponk(13, relativeTo: .caption)).foregroundStyle(Color.ponkMuted).italic()
                }
                HStack(spacing: 8) {
                    stepper
                    Spacer(minLength: 4)
                    if let t = entry.lineTotal {
                        Text("\(money(t)) Kč")
                            .font(.ponk(16, .heavy))
                            .monospacedDigit()
                            .foregroundStyle(entry.isChecked ? Color.ponkMuted : Color.ponkInk)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if let s = shelf {
                Text("Regál \(s.shelf)" + (s.field.isEmpty || s.field == "0" ? "" : ", pole \(s.field)"))
                    .font(.ponk(13, .semibold, relativeTo: .caption))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Color.ponkLabelInk)
                    .background(Color.ponkLabel, in: RoundedRectangle(cornerRadius: 2))
            }
            if let p = entry.product {
                if !p.isListed {
                    Text("Není v nabídce").foregroundStyle(Color.ponkRedDeep)
                } else if let q = stock {
                    if q >= entry.qty {
                        Text("Skladem \(money(q)) ks").foregroundStyle(Color.ponkGreen)
                    } else if q > 0 {
                        Text("Jen \(money(q)) ks").foregroundStyle(Color.ponkRedDeep)
                    } else {
                        Text("Na prodejně není").foregroundStyle(Color.ponkRedDeep)
                    }
                }
                if let was = entry.added_price, let now = p.price, abs(was - now) >= 1 {
                    Text(now < was ? "↓ \(money(was - now)) Kč" : "↑ \(money(now - was)) Kč")
                        .foregroundStyle(now < was ? Color.ponkGreen : Color.ponkRedDeep)
                }
            }
        }
        .font(.ponk(13, .semibold, relativeTo: .caption))
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            Button { onQty(entry.qty - 1) } label: {
                Image(systemName: entry.qty <= 1 ? "trash" : "minus").frame(width: 34, height: 30)
            }
            .accessibilityLabel(entry.qty <= 1 ? "Odebrat" : "Méně")
            Text("\(qtyText(entry.qty)) ks")
                .font(.ponk(15, .semibold))
                .monospacedDigit()
                .frame(minWidth: 44)
            Button { onQty(entry.qty + 1) } label: {
                Image(systemName: "plus").frame(width: 34, height: 30)
            }
            .accessibilityLabel("Více")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.ponkInk)
        .background(Color.ponkSurface2, in: Capsule())
    }
}

// MARK: - přidání do seznamu z detailu produktu

struct AddToListSheet: View {
    let sku: String
    let name: String
    var onDone: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currentList") private var currentID = 0
    @State private var lists: [ShoppingListInfo] = []
    @State private var listID = 0
    @State private var qty = 1
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(name).font(.ponk(16, .semibold)).lineLimit(2)
                    Stepper(value: $qty, in: 1...999) {
                        Text("Množství: \(qty) ks").font(.ponk(17)).monospacedDigit()
                    }
                }
                Section("Seznam") {
                    Picker("Seznam", selection: $listID) {
                        ForEach(lists) { Text("\($0.name) (\($0.open))").tag($0.id) }
                        Text("Nový seznam…").tag(-1)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if listID == -1 {
                        TextField("Název nového seznamu", text: $newName)
                    }
                }
            }
            .font(.ponk(17))
            .navigationTitle("Do seznamu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") { Task { await add() } }
                        .disabled(listID == -1 && newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                lists = (try? await app.api.get("lists", as: ListResponse<ShoppingListInfo>.self).items) ?? []
                listID = lists.contains { $0.id == currentID } ? currentID : (lists.first?.id ?? -1)
            }
        }
    }

    private func add() async {
        var target = listID
        if target == -1 {
            try? await app.api.send("POST", "lists", body: ["name": newName])
            target = (try? await app.api.get("lists", as: ListResponse<ShoppingListInfo>.self).items.last?.id) ?? 0
        }
        try? await app.api.send("POST", "list/\(target)", body: ["sku": sku, "qty": qty])
        currentID = target
        onDone()
        dismiss()
    }
}

// MARK: - mapa trasy

/// Plánek prodejny s očíslovanými zastávkami v pořadí, v jakém se položky sbírají.
struct ListMapSheet: View {
    struct Stop: Hashable {
        let shelf: String
        let field: String
        let title: String
        var number: Int? { Int(shelf.prefix { $0.isNumber }) }
    }

    let store: String
    let storeName: String
    let stops: [Stop]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var map: StoreMap?
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let map, let image {
                    RouteCanvas(map: map, image: image, pins: pins(map))
                        .background(Color.white)
                        .frame(maxHeight: .infinity)
                    List {
                        ForEach(Array(stops.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.ponk(14, .heavy))
                                    .frame(width: 26, height: 26)
                                    .foregroundStyle(.white)
                                    .background(Color.ponkRed, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.ponk(15, .semibold)).lineLimit(1)
                                    Text("Regál \(s.shelf)" + (s.field.isEmpty || s.field == "0" ? "" : ", pole \(s.field)"))
                                        .font(.ponk(13)).foregroundStyle(Color.ponkMuted)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 230)
                } else if let error {
                    ContentUnavailableView("Mapu nejde zobrazit", systemImage: "map", description: Text(error))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { dismiss() } } }
        }
        .task { await load() }
    }

    struct Pin: Identifiable {
        let id: Int
        let point: CGPoint
    }

    /// Zastávky na stejném štítku regálu se rozloží kolem něj, aby se nepřekrývaly.
    private func pins(_ map: StoreMap) -> [Pin] {
        var used: [String: Int] = [:]
        var out: [Pin] = []
        for (i, s) in stops.enumerated() {
            guard let n = s.number, let l = map.labels.first(where: { $0.lo <= n && n <= $0.hi }) else { continue }
            let key = "\(l.x),\(l.y)"
            let k = used[key, default: 0]
            used[key] = k + 1
            let angle = Double(k) * 1.1
            let r: Double = k == 0 ? 0 : 16 + Double(k) * 3
            out.append(Pin(id: i + 1, point: CGPoint(x: l.box.midX + cos(angle) * r, y: l.box.midY + sin(angle) * r)))
        }
        return out
    }

    private func load() async {
        do {
            let m = try await app.api.get("storemap/\(store)", as: StoreMap.self)
            map = m
            guard let url = URL(string: m.image), let img = await ImageCache.shared.load(url) else {
                error = "Plánek se nepodařilo stáhnout. Jsi online?"
                return
            }
            image = img
        } catch {
            self.error = "Pro tuto prodejnu zatím plánek nemám."
        }
    }
}

private struct RouteCanvas: View {
    let map: StoreMap
    let image: UIImage
    let pins: [ListMapSheet.Pin]
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / map.width, geo.size.height / map.height)
            let w = map.width * fit, h = map.height * fit
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: w, height: h)
                ForEach(pins) { p in
                    Text("\(p.id)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.ponkRed, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(radius: 1.5)
                        .scaleEffect(1 / max(scale, 1) * 1.2)
                        .position(x: p.point.x * fit, y: p.point.y * fit)
                }
            }
            .frame(width: w, height: h)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(6, max(1, baseScale * v.magnification)) }
                    .onEnded { _ in baseScale = scale }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height) }
                    .onEnded { _ in baseOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.35)) {
                    if scale > 1.05 { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero } else { scale = 2.2; baseScale = 2.2 }
                }
            }
        }
    }
}
