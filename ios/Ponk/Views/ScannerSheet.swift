import SwiftUI
import UIKit
import VisionKit

/// Skener do prodejny: namíříš na čárový kód zboží nebo cenovky a hned vidíš cenu, jestli je
/// opravdu výhodná (nejnižší cena za 30 dní), sklad a regál ve své prodejně a akci výrobce.
/// Skenuje se průběžně: další kód přidá další kartu, předchozí zůstanou v historii dole.
struct ScannerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    @State private var hits: [ScanHit] = []
    @State private var lastCode = ""
    @State private var lastAt = Date.distantPast
    @State private var addFor: Item?
    @State private var toast: String?
    @State private var foundTick = 0
    @State private var missTick = 0

    private var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                if supported {
                    BarcodeScanner(active: path.isEmpty && addFor == nil) { handle($0) }
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Čtečka není dostupná", systemImage: "barcode.viewfinder",
                                           description: Text("Povol Ponku přístup ke kameře v Nastavení, nebo tento iPhone čtení kódů nepodporuje."))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .bottom) { bottom }
            .overlay(alignment: .top) {
                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.ponk(15, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .ponkGlassCapsule(tint: Color.ponkGreen.opacity(0.35))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Skener")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } }
            }
            .ponkDestinations()
        }
        .sensoryFeedback(.success, trigger: foundTick)
        .sensoryFeedback(.warning, trigger: missTick)
        .sheet(item: $addFor) { item in
            AddToListSheet(sku: item.sku, name: item.name) { show("Přidáno do seznamu") }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - spodní část: karta posledního kódu a historie

    private var bottom: some View {
        VStack(spacing: 10) {
            if let h = hits.first {
                ScanCard(hit: h, store: app.myStore, storeName: app.storeName(app.myStore),
                         onDetail: { path.append(ProductRoute(sku: $0)) },
                         onList: { addFor = $0 },
                         onWatch: { watch($0) })
                    .id(h.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                Text("Namiř na čárový kód na zboží nebo cenovce")
                    .font(.ponk(16, .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .ponkGlassCapsule(tint: Color.black.opacity(0.2))
            }
            if hits.count > 1 { history }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: hits.map(\.id))
    }

    /// Dříve naskenované: klepnutím se karta vrátí nahoru.
    private var history: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(hits.dropFirst().prefix(15))) { h in
                    Button {
                        if let i = hits.firstIndex(where: { $0.id == h.id }) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { hits.insert(hits.remove(at: i), at: 0) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ProductImage(path: h.item?.image ?? h.live?.image, w: 80, h: 99)
                                .frame(width: 26, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text((h.item?.price ?? h.live?.price).map { "\(money($0)) Kč" } ?? h.code)
                                .font(.ponk(14, .heavy))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .foregroundStyle(Color.ponkInk)
                        .ponkGlassCapsule(tint: .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - akce

    private func handle(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        // stejný kód před kamerou se nenačítá pořád dokola
        if code == lastCode, Date().timeIntervalSince(lastAt) < 3 { return }
        lastCode = code
        lastAt = .now
        if hits.first?.code == code { return }
        if let i = hits.firstIndex(where: { $0.code == code }) {
            withAnimation { hits.insert(hits.remove(at: i), at: 0) }
            foundTick += 1
            return
        }
        let hit = ScanHit(code: code)
        withAnimation { hits.insert(hit, at: 0) }
        Task { await resolve(hit.id, code) }
    }

    private func resolve(_ id: UUID, _ code: String) async {
        let items = (try? await app.api.get("ean/\(code)", as: ListResponse<Item>.self).items) ?? []
        if let item = items.first {
            update(id) { $0.item = item; $0.state = .found }
            foundTick += 1
            if let store = app.myStore {
                let live = await BauhausLive.shelves(skus: [item.sku], store: store)
                update(id) { h in
                    h.shelf = live.shelves[item.sku]
                    if let q = live.stock[item.sku]?[store] { h.qty = q } else if !live.stock.isEmpty { h.qty = 0 }
                }
            }
        } else if let l = await BauhausLive.lookupEAN(code) {
            update(id) { $0.live = ScanHit.Live(sku: l.sku, name: l.name, image: l.image, price: l.price, url: l.url); $0.state = .live }
            foundTick += 1
        } else {
            update(id) { $0.state = .notFound }
            missTick += 1
        }
    }

    private func update(_ id: UUID, _ change: (inout ScanHit) -> Void) {
        guard let i = hits.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { change(&hits[i]) }
    }

    private func watch(_ item: Item) {
        Task {
            try? await app.api.send("POST", "watch", body: ["sku": item.sku, "keep": true])
            show("Hlídám cenu")
        }
    }

    private func show(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }
}

/// Jeden naskenovaný kód a co se k němu našlo.
struct ScanHit: Identifiable {
    enum State { case loading, found, live, notFound }
    struct Live { let sku: String; let name: String; let image: String?; let price: Double?; let url: URL? }

    let id = UUID()
    let code: String
    var state: State = .loading
    var item: Item?
    var live: Live?
    var shelf: BauhausLive.Shelf?
    var qty: Double?
}

/// Karta výsledku: cena, verdikt, sklad a regál v mé prodejně, akce a rychlé akce.
private struct ScanCard: View {
    let hit: ScanHit
    let store: String?
    let storeName: String
    var onDetail: (String) -> Void
    var onList: (Item) -> Void
    var onWatch: (Item) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch hit.state {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Hledám \(hit.code)…").font(.ponk(16, .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            case .notFound:
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kód \(hit.code) Bauhaus nezná").font(.ponk(16, .semibold))
                        Text("Zkus kód na cenovce u regálu.").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                    }
                } icon: { Image(systemName: "questionmark.circle").foregroundStyle(Color.ponkMuted) }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            case .live:
                if let l = hit.live { liveCard(l) }
            case .found:
                if let item = hit.item { found(item) }
            }
        }
        .foregroundStyle(Color.ponkInk)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ponkGlassPanel(cornerRadius: 22)
    }

    @ViewBuilder
    private func found(_ item: Item) -> some View {
        let v = verdict(item)
        Button { onDetail(item.sku) } label: {
            HStack(alignment: .top, spacing: 12) {
                ProductImage(path: item.image, w: 200, h: 248)
                    .frame(width: 66, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.ponk(16, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        PriceTag(price: item.price, discount: item.real_discount)
                        if item.labels.contains("gift") {
                            Flag(text: "Dárek k nákupu", color: Color(light: 0xF2C300, dark: 0xF2C300),
                                 ink: Color(light: 0x1A1A1A, dark: 0x1A1A1A))
                        } else if item.labels.contains("sell_off") {
                            Flag(text: "Výprodej", color: .ponkRed, ink: .white)
                        }
                    }
                    Text(v.text).font(.ponk(14, .semibold)).foregroundStyle(v.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ponkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if store != nil {
            stockLine(qty: hit.qty ?? item.store_qty)
        }

        HStack(spacing: 8) {
            Button { onList(item) } label: { Label("Do seznamu", systemImage: "checklist").frame(maxWidth: .infinity) }
                .ponkProminentButton()
            Button { onWatch(item) } label: { Label("Hlídat", systemImage: "eye").frame(maxWidth: .infinity) }
                .ponkGlassButton()
        }
        .font(.ponk(15, .semibold))
        .controlSize(.large)
    }

    private func stockLine(qty: Double?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.ponkMuted)
            if let q = qty {
                Text(q > 0 ? "\(storeName): \(money(q)) ks" : "\(storeName): není skladem")
                    .foregroundStyle(q > 0 ? Color.ponkGreen : Color.ponkRedDeep)
            } else {
                Text(storeName).foregroundStyle(Color.ponkMuted)
            }
            if let s = hit.shelf {
                Text("Regál \(s.shelf)" + (s.field.isEmpty || s.field == "0" ? "" : ", pole \(s.field)"))
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(Color.ponkLabelInk)
                    .background(Color.ponkLabel, in: RoundedRectangle(cornerRadius: 2))
                    .lineLimit(1).fixedSize()
            }
        }
        .font(.ponk(14, .semibold))
    }

    @ViewBuilder
    private func liveCard(_ l: ScanHit.Live) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProductImage(path: l.image, w: 200, h: 248)
                .frame(width: 66, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text(l.name).font(.ponk(16, .semibold)).lineLimit(2)
                PriceTag(price: l.price, discount: nil)
                Text("Nový produkt, v Ponku zatím bez historie ceny.").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
            }
        }
        if let url = l.url {
            Button { openURL(url) } label: { Label("Otevřít na bauhaus.cz", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                .ponkGlassButton()
                .font(.ponk(15, .semibold))
                .controlSize(.large)
        }
    }

    /// Je cena opravdu dobrá? Podle nejnižší ceny za 30 dní a poslední změny.
    private func verdict(_ item: Item) -> (text: String, color: Color) {
        guard item.isListed, let price = item.price else {
            return ("Bauhaus tento produkt už nenabízí", .ponkRedDeep)
        }
        if let d = item.real_discount, d > 0 {
            return ("Skutečná sleva \(d) % oproti nejnižší ceně za 30 dní", .ponkGreen)
        }
        if let min30 = item.min30_price, price > min30 + 0.5 {
            return ("Za posledních 30 dní byla i za \(money(min30)) Kč", .ponkRedDeep)
        }
        if let prev = item.prev_price, prev > price + 0.5 {
            return ("Zlevněno z \(money(prev)) Kč \(shortDay(item.price_changed_at))", .ponkGreen)
        }
        if let prev = item.prev_price, price > prev + 0.5 {
            return ("Zdraženo z \(money(prev)) Kč \(shortDay(item.price_changed_at))", .ponkRedDeep)
        }
        return ("Cena se v poslední době nemění", .ponkMuted)
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    /// Když je nahoře detail produktu nebo jiný list, kamera se pozastaví.
    var active: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if active, !vc.isScanning { try? vc.startScanning() }
        if !active, vc.isScanning { vc.stopScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue, !value.isEmpty {
                    onCode(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let code) = item, let value = code.payloadStringValue { onCode(value) }
        }
    }
}
