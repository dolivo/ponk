import SwiftUI

// --- cenovka: hlavní výrazový prvek, stejný jako na webu --------------------

struct PriceTag: View {
    let price: Double?
    let discount: Int?
    var big = false

    var body: some View {
        let sale = (discount ?? 0) > 0
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(money(price))
                    .font(.ponk(big ? 40 : 21, .heavy, relativeTo: big ? .largeTitle : .title3))
                    .monospacedDigit()
                Text("Kč").font(.ponk(big ? 22 : 13, .semibold, relativeTo: .caption))
            }
            .lineLimit(1)
            .padding(.horizontal, big ? 12 : 7)
            .padding(.vertical, big ? 6 : 3)
            .frame(maxHeight: .infinity)
            .foregroundStyle(sale ? Color.white : Color.ponkInk)
            .background(sale ? Color.ponkRed : Color.ponkSurface)

            if sale, let d = discount {
                Text("−\(d) %")
                    .font(.ponk(big ? 20 : 14, .heavy, relativeTo: .caption))
                    .lineLimit(1)
                    .padding(.horizontal, big ? 12 : 6)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(Color(light: 0xCC0000, dark: 0xC8102E))
                    .background(Color.white)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(sale ? Color.ponkRed : Color.ponkInk, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sale ? "\(money(price)) korun, sleva \(discount ?? 0) procent" : "\(money(price)) korun")
    }
}

struct ProductImage: View {
    let path: String?
    var w = 300
    var h = 372

    var body: some View {
        Color.white
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: productImageURL(path, w: w, h: h)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").font(.title2).foregroundStyle(.gray)
                    default: Color.clear
                    }
                }
                .padding(8)
            }
            .clipped()
    }
}

struct Flag: View {
    let text: String
    var color: Color = .ponkLabel
    var ink: Color = .ponkLabelInk

    var body: some View {
        Text(text)
            .font(.ponk(12, .heavy, relativeTo: .caption2))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(ink)
            .background(color, in: RoundedRectangle(cornerRadius: 2))
    }
}

struct Flags: View {
    let item: Item
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.labels.contains("sell_off") { Flag(text: "Výprodej", color: .ponkRed, ink: .white) }
            if let changed = item.price_changed_at, changed == app.meta?.last_change, (item.drop_pct ?? 0) > 0 {
                Flag(text: "Zlevněno", color: .ponkGreen, ink: .white)
            }
            if item.labels.contains("only_online") { Flag(text: "Jen online") }
        }
    }
}

struct PriceMeta: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let min30 = item.min30_price, (item.real_discount ?? 0) > 0 {
                Text("nejníže za 30 dní \(money(min30)) Kč")
            } else if let was = item.was_price {
                Text("\(money(was)) Kč").strikethrough()
            }
            if let prev = item.prev_price, let price = item.price, let changed = item.price_changed_at {
                let diff = price - prev
                Text("\(diff < 0 ? "↓" : "↑") \(money(abs(diff))) Kč \(shortDay(changed))")
                    .foregroundStyle(diff < 0 ? Color.ponkGreen : Color.ponkRedDeep)
                    .fontWeight(.semibold)
            }
            if let unit = item.unit_price, let u = item.unit {
                Text("\(money2(unit)) Kč/\(u)")
            }
        }
        .font(.ponk(13, relativeTo: .caption))
        .foregroundStyle(Color.ponkMuted)
    }
}

struct Availability: View {
    let item: Item
    @Environment(AppModel.self) private var app

    var body: some View {
        let qty = item.store_qty ?? 0
        HStack(spacing: 5) {
            Circle().frame(width: 7, height: 7)
            if qty > 0, let store = app.myStore {
                Text("\(app.storeName(store)): \(money(qty)) ks").fontWeight(.semibold)
            } else if item.online_in_stock == 1 {
                Text("Skladem online")
            } else {
                Text("Nedostupné")
            }
        }
        .font(.ponk(13, relativeTo: .caption))
        .foregroundStyle(qty > 0 ? Color.ponkGreen : Color.ponkMuted)
    }
}

private func nameText(_ item: Item, size: CGFloat) -> Text {
    if let brand = item.brand, item.name.hasPrefix(brand) {
        let rest = String(item.name.dropFirst(brand.count))
        return Text("\(Text(brand).font(.ponk(size, .semibold)))\(Text(rest).font(.ponk(size)))")
    }
    return Text(item.name).font(.ponk(size))
}

/// Dlaždice jako přihrádka v regálu.
struct ProductTile: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductImage(path: item.image)
                .overlay(alignment: .topLeading) { Flags(item: item).padding(8) }
            VStack(alignment: .leading, spacing: 6) {
                nameText(item, size: 15)
                    .foregroundStyle(Color.ponkInk)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                Spacer(minLength: 0)
                PriceTag(price: item.price, discount: item.real_discount)
                PriceMeta(item: item)
                Availability(item: item)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.ponkSurface)
        .contentShape(Rectangle())
    }
}

struct ProductRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductImage(path: item.image, w: 200, h: 248)
                .frame(width: 88)
                .overlay(alignment: .topLeading) { Flags(item: item).scaleEffect(0.85, anchor: .topLeading).padding(4) }
            VStack(alignment: .leading, spacing: 6) {
                nameText(item, size: 15).foregroundStyle(Color.ponkInk).lineLimit(2)
                PriceTag(price: item.price, discount: item.real_discount)
                PriceMeta(item: item)
                Availability(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ponkSurface)
        .contentShape(Rectangle())
    }
}

/// Mřížka produktů s 1px mezerami (regál).
struct Shelf: View {
    let items: [Item]
    var list = false
    var onLast: (() -> Void)? = nil

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
        Group {
            if list {
                LazyVStack(spacing: 1) {
                    ForEach(items) { item in
                        NavigationLink(value: ProductRoute(sku: item.sku)) { ProductRow(item: item) }
                            .buttonStyle(.plain)
                            .onAppear { if item.id == items.last?.id { onLast?() } }
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(items) { item in
                        NavigationLink(value: ProductRoute(sku: item.sku)) { ProductTile(item: item) }
                            .buttonStyle(.plain)
                            .onAppear { if item.id == items.last?.id { onLast?() } }
                    }
                }
            }
        }
        .padding(.vertical, 1)
        .background(Color.ponkShelf)
    }
}

struct Rail: View {
    let items: [Item]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // obyčejný HStack + fixedSize: všechny dlaždice v řadě mají stejnou výšku
            HStack(spacing: 1) {
                ForEach(items) { item in
                    NavigationLink(value: ProductRoute(sku: item.sku)) { ProductTile(item: item) }
                        .buttonStyle(.plain)
                        .frame(width: 172)
                        .frame(maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .padding(.vertical, 1)
        .background(Color.ponkShelf)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ponk(21, .heavy, relativeTo: .title2)).foregroundStyle(Color.ponkInk)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Upozornění, že data v telefonu jsou starší než dva dny.
struct OfflineNotice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let since = app.api.offlineSince {
            Label("Starší data z \(since.formatted(.dateTime.day().month(.defaultDigits).hour().minute().locale(Locale(identifier: "cs_CZ")))). Stáhni nová ve Více.",
                  systemImage: "clock.arrow.circlepath")
                .font(.ponk(14, .semibold, relativeTo: .footnote))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .ponkGlassCapsule(tint: Color.orange.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Data se nepodařilo načíst", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Zkusit znovu", action: retry).ponkProminentButton()
        }
    }
}

extension View {
    /// Cíle navigace společné pro všechny záložky.
    func ponkDestinations() -> some View {
        navigationDestination(for: ProductRoute.self) { ProductView(sku: $0.sku) }
            .navigationDestination(for: ResultsRoute.self) { ResultsView(route: $0) }
            .navigationDestination(for: CategoryRoute.self) { CategoryBrowser(cat1: $0.cat1, cat2: $0.cat2) }
    }

    func ponkPage() -> some View {
        background(Color.ponkPage.ignoresSafeArea())
    }
}

// --- Liquid Glass jen na iOS 26+, na starších verzích běžné styly ------------

extension View {
    @ViewBuilder
    func ponkGlassButton() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }

    @ViewBuilder
    func ponkProminentButton() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder
    func ponkGlassCapsule(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            self.background(.thinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func ponkMinimizingTabBar() -> some View {
        if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(.onScrollDown) } else { self }
    }
}

/// Skupina skleněných prvků, které se na iOS 26 slévají dohromady.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
