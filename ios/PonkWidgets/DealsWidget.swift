import SwiftUI
import UIKit
import WidgetKit

/// Widget na plochu: největší zlevnění z poslední ranní kontroly cen (z GitHubu, stejná data
/// jako aplikace). Klepnutí otevře produkt v Ponku.
struct Deal: Codable, Hashable {
    let sku: String
    let name: String
    let price: Double
    let prev: Double?
    let pct: Double?
    let image: String?
}

struct DealsEntry: TimelineEntry {
    let date: Date
    let title: String
    let deals: [Deal]
    let images: [String: Data]
}

struct DealsProvider: TimelineProvider {
    static let statusURL = URL(string: "https://github.com/dolivo/ponk/releases/download/data/status.json")!

    func placeholder(in context: Context) -> DealsEntry {
        DealsEntry(date: .now, title: "Zlevněno dnes", deals: [
            Deal(sku: "0", name: "Ryobi ONE+ Aku vrtací šroubovák", price: 1290, prev: 1590, pct: 18.9, image: nil),
            Deal(sku: "1", name: "Osram LED žárovka", price: 179, prev: 229, pct: 21.8, image: nil),
            Deal(sku: "2", name: "Novaservis kulový kohout", price: 130, prev: 149, pct: 12.8, image: nil),
        ], images: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (DealsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await load(count: context.family == .systemSmall ? 1 : 3)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DealsEntry>) -> Void) {
        Task {
            let entry = await load(count: context.family == .systemSmall ? 1 : 3)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3 * 3600))))
        }
    }

    private struct Status: Codable {
        let top_drops: [Deal]?
        let top_deals: [Deal]?
    }

    private func load(count: Int) async -> DealsEntry {
        var title = "Zlevněno dnes"
        var deals: [Deal] = []
        if let (data, _) = try? await URLSession.shared.data(from: Self.statusURL),
           let s = try? JSONDecoder().decode(Status.self, from: data) {
            deals = s.top_drops ?? []
            if deals.isEmpty { deals = s.top_deals ?? []; title = "Největší slevy" }
        }
        deals = Array(deals.prefix(count))
        var images: [String: Data] = [:]
        for d in deals {
            guard let path = d.image, let url = URL(string: "https://www.bauhaus.cz/img/160/198/resize/catalog/product\(path)") else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url), UIImage(data: data) != nil { images[d.sku] = data }
        }
        return DealsEntry(date: .now, title: title, deals: deals, images: images)
    }
}

struct DealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PonkDeals", provider: DealsProvider()) { entry in
            DealsView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Zlevněno v Bauhausu")
        .description("Největší zlevnění z ranní kontroly cen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DealsView: View {
    let entry: DealsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.deals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer()
                Text("Data se načtou, až bude internet.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall, let d = entry.deals.first {
            VStack(alignment: .leading, spacing: 4) {
                header
                HStack(alignment: .top) {
                    image(d).frame(width: 52, height: 52)
                    Spacer(minLength: 0)
                    if let p = d.pct { Text("−\(Int(p.rounded())) %").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(WColor.green) }
                }
                Text(d.name).font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                price(d)
            }
            .widgetURL(URL(string: "ponk://product/\(d.sku)"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                ForEach(entry.deals, id: \.sku) { d in
                    Link(destination: URL(string: "ponk://product/\(d.sku)")!) {
                        HStack(spacing: 8) {
                            image(d).frame(width: 34, height: 34)
                            Text(d.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            price(d)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill").foregroundStyle(WColor.red)
            Text(entry.title).font(.caption.weight(.heavy))
        }
    }

    @ViewBuilder
    private func image(_ d: Deal) -> some View {
        if let data = entry.images[d.sku], let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit()
                .padding(2).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15))
        }
    }

    private func price(_ d: Deal) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(wMoney(d.price)).font(.system(.subheadline, design: .rounded).weight(.heavy))
                .padding(.horizontal, 4)
                .background(WColor.yellow, in: RoundedRectangle(cornerRadius: 2))
                .foregroundStyle(.black)
            if let prev = d.prev { Text(wMoney(prev)).font(.caption2).strikethrough().foregroundStyle(.secondary) }
        }
    }
}
