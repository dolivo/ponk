import SwiftUI
import UIKit
import WidgetKit

/// Widget „Můj Bauhaus“: hlídané, nákupní seznam, dnešní zlevnění a novinky skladem v mé
/// prodejně. Osobní data posílá aplikace (WidgetShare), zlevnění si widget bere ze status.json.
struct MineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let deal: Deal?
    let images: [String: Data]
}

struct MineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MineEntry {
        MineEntry(date: .now, snapshot: WidgetSnapshot(
            updated: .now, storeName: "Brno Ivanovice", watchTotal: 4, watchDropped: 2,
            watchTop: .init(sku: "0", name: "Ryobi ONE+ Aku vrtací šroubovák RDD18-0", price: 2190, image: nil, drop: 300),
            list: .init(id: 1, name: "Koupelna", done: 2, total: 6, sum: 1817),
            restockDay: nil, restockCount: 5,
            restock: [.init(sku: "1", name: "Dulux Easycare Barva na stěnu", price: 549, image: nil, drop: nil),
                      .init(sku: "2", name: "Akustický obkladový panel", price: 1450, image: nil, drop: nil),
                      .init(sku: "3", name: "Schneider Acti 9 Jistič", price: 149, image: nil, drop: nil)]),
                  deal: Deal(sku: "4", name: "Sencor Bezdrátová meteostanice SWS 3000 W", price: 259, prev: 549, pct: 52.8, image: nil),
                  images: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (MineEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await load(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MineEntry>) -> Void) {
        Task {
            let entry = await load(family: context.family)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3 * 3600))))
        }
    }

    private struct Status: Codable {
        let top_drops: [Deal]?
        let top_deals: [Deal]?
    }

    private func load(family: WidgetFamily) async -> MineEntry {
        let snapshot = WidgetShare.load()
        var deal: Deal?
        if family == .systemLarge || snapshot == nil,
           let (data, _) = try? await URLSession.shared.data(from: DealsProvider.statusURL),
           let s = try? JSONDecoder().decode(Status.self, from: data) {
            deal = (s.top_drops ?? []).first ?? (s.top_deals ?? []).first
        }
        // fotky: jen ty, které se v dané velikosti opravdu zobrazí
        var wanted: [String: String] = [:]
        if let snapshot {
            for p in snapshot.restock { if let i = p.image { wanted[p.sku] = i } }
            if family == .systemLarge, let w = snapshot.watchTop, let i = w.image { wanted[w.sku] = i }
        }
        if let deal, let i = deal.image { wanted[deal.sku] = i }
        let images = await withTaskGroup(of: (String, Data?).self) { group in
            for (sku, path) in wanted {
                group.addTask {
                    guard let url = URL(string: "https://www.bauhaus.cz/img/160/198/resize/catalog/product\(path)"),
                          let (data, _) = try? await URLSession.shared.data(from: url), UIImage(data: data) != nil else { return (sku, nil) }
                    return (sku, data)
                }
            }
            var out: [String: Data] = [:]
            for await (sku, data) in group { if let data { out[sku] = data } }
            return out
        }
        return MineEntry(date: .now, snapshot: snapshot, deal: deal, images: images)
    }
}

struct MineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PonkMine", provider: MineProvider()) { entry in
            MineView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Můj Bauhaus")
        .description("Hlídané, nákupní seznam, dnešní zlevnění a novinky skladem v tvé prodejně.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - vzhled

private enum MFont {
    static func regular(_ s: CGFloat) -> Font { .custom("BarlowSemiCondensed-Regular", size: s) }
    static func semibold(_ s: CGFloat) -> Font { .custom("BarlowSemiCondensed-SemiBold", size: s) }
    static func heavy(_ s: CGFloat) -> Font { .custom("BarlowSemiCondensed-ExtraBold", size: s) }
}

struct MineView: View {
    let entry: MineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge { large } else { medium }
    }

    // MARK: střední: nově skladem

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox").font(.system(size: 13, weight: .bold)).foregroundStyle(WColor.red)
                Text("Nově skladem").font(MFont.heavy(15))
                Spacer(minLength: 4)
                if let s = entry.snapshot {
                    Text("\(s.storeName) · \(whenCount(s.restockDay, s.restockCount, nil))")
                        .font(MFont.regular(12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let s = entry.snapshot, !s.restock.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(s.restock, id: \.sku) { p in
                        Link(destination: productURL(p.sku)) {
                            VStack(alignment: .leading, spacing: 3) {
                                thumb(p.sku).frame(maxWidth: .infinity).frame(height: 52)
                                Text(p.name).font(MFont.semibold(12)).lineLimit(1)
                                if let price = p.price { Text(wMoney(price)).font(MFont.heavy(14)) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(0..<max(0, 3 - s.restock.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            } else if entry.snapshot != nil {
                Spacer(minLength: 0)
                Text("V tvé prodejně teď nic nového nepřibylo.").font(MFont.regular(13)).foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                hint
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
    }

    // MARK: velký: vše v jednom

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Můj Bauhaus").font(MFont.heavy(18))
                Spacer(minLength: 4)
                if let s = entry.snapshot { Text(s.storeName).font(MFont.regular(12)).foregroundStyle(.secondary).lineLimit(1) }
            }
            if let s = entry.snapshot {
                watchRow(s)
                divider
                listRow(s)
                divider
                if let d = entry.deal { dealRow(d); divider }
                restockRow(s)
            } else {
                if let d = entry.deal { dealRow(d); divider }
                hint
            }
            Spacer(minLength: 0)
        }
    }

    private func watchRow(_ s: WidgetSnapshot) -> some View {
        Link(destination: s.watchTop.map { productURL($0.sku) } ?? URL(string: "ponk://watch")!) {
            HStack(spacing: 10) {
                if let w = s.watchTop { thumb(w.sku).frame(width: 40, height: 40) }
                VStack(alignment: .leading, spacing: 1) {
                    caption("eye", s.watchDropped > 0 ? "HLÍDANÉ · \(s.watchDropped) \(plural(s.watchDropped, "ZLEVNIL", "ZLEVNILY", "ZLEVNILO"))"
                                                      : "HLÍDANÉ · \(s.watchTotal)")
                    Text(s.watchTop?.name ?? "Zatím nic nehlídáš – v detailu produktu klepni na Hlídat.")
                        .font(MFont.semibold(13)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let w = s.watchTop {
                    VStack(alignment: .trailing, spacing: 0) {
                        if let p = w.price { Text(wMoney(p)).font(MFont.heavy(15)) }
                        if let drop = w.drop, drop >= 1 {
                            Text("↓ \(wMoney(drop))").font(MFont.heavy(12)).foregroundStyle(WColor.green)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ s: WidgetSnapshot) -> some View {
        if let l = s.list {
            HStack(spacing: 10) {
                Link(destination: URL(string: "ponk://list")!) {
                    VStack(alignment: .leading, spacing: 4) {
                        caption("checklist", "SEZNAM · \(l.name.uppercased())")
                        if l.total == 0 {
                            Text("Seznam je prázdný").font(MFont.heavy(15))
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(l.done) z \(l.total) v košíku").font(MFont.heavy(15))
                                if l.sum > 0 { Text(wMoney(l.sum)).font(MFont.regular(13)).foregroundStyle(.secondary) }
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.2))
                                    Capsule().fill(WColor.red).frame(width: g.size.width * CGFloat(l.done) / CGFloat(max(1, l.total)))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if l.done < l.total {
                    Link(destination: URL(string: "ponk://shop/\(l.id)")!) {
                        Text("Nakupuji").font(MFont.heavy(14)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(WColor.red, in: Capsule())
                    }
                }
            }
        }
    }

    private func dealRow(_ d: Deal) -> some View {
        Link(destination: productURL(d.sku)) {
            HStack(spacing: 10) {
                thumb(d.sku).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    caption("tag", "ZLEVNĚNO DNES")
                    Text(d.name).font(MFont.semibold(13)).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(wMoney(d.price)).font(MFont.heavy(15)).foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .background(WColor.yellow, in: RoundedRectangle(cornerRadius: 3))
                    if let p = d.pct { Text("−\(Int(p.rounded())) %").font(MFont.heavy(12)).foregroundStyle(WColor.red) }
                }
            }
        }
    }

    private func restockRow(_ s: WidgetSnapshot) -> some View {
        Link(destination: s.restock.first.map { productURL($0.sku) } ?? URL(string: "ponk://list")!) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    caption("shippingbox", "NOVĚ SKLADEM")
                    Text(s.restockCount > 0
                         ? whenCount(s.restockDay, s.restockCount, ("produkt", "produkty", "produktů")).capitalizedFirst
                         : "Zatím nic nového")
                        .font(MFont.semibold(13)).lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ForEach(s.restock, id: \.sku) { p in thumb(p.sku).frame(width: 32, height: 32) }
                }
            }
        }
    }

    // MARK: drobnosti

    private var hint: some View {
        Text("Otevři Ponk – hlídané, nákupní seznam a novinky skladem se sem načtou.")
            .font(MFont.regular(13)).foregroundStyle(.secondary)
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
    }

    private func caption(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            Text(text).font(MFont.heavy(11)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func thumb(_ sku: String) -> some View {
        if let data = entry.images[sku], let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit()
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7).fill(Color.gray.opacity(0.12))
        }
    }

    private func productURL(_ sku: String) -> URL { URL(string: "ponk://product/\(sku)")! }

    /// „dnes“, „včera“ nebo datum dne s novinkami.
    private func dayWord(_ day: String?) -> String {
        guard let day else { return "dnes" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return "dnes" }
        if Calendar.current.isDateInToday(d) { return "dnes" }
        if Calendar.current.isDateInYesterday(d) { return "včera" }
        f.dateFormat = "d. M."
        return f.string(from: d)
    }

    /// „dnes 5 produktů“, „včera 3 produkty“, „14. 11.: 2 produkty“.
    private func whenCount(_ day: String?, _ n: Int, _ noun: (String, String, String)?) -> String {
        let when = dayWord(day)
        let count = noun.map { "\(n) \(plural(n, $0.0, $0.1, $0.2))" } ?? "\(n)"
        return when.first?.isNumber == true ? "\(when): \(count)" : "\(when) \(count)"
    }

    /// České tvary: 1 produkt, 2–4 produkty, 5+ produktů.
    private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        n == 1 ? one : (2...4).contains(n) ? few : many
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
