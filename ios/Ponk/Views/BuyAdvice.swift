import SwiftUI

/// „Kdy koupit“: odhad z historie ceny, nejnižší ceny za 30 dní, výprodeje, akcí výrobce
/// a obvyklých sezónních výprodejů. Je to vodítko, ne předpověď – Bauhaus může cenu změnit kdykoli.
struct BuyAdvice {
    enum Level { case buy, wait, neutral }

    let level: Level
    let reasons: [String]

    var title: String {
        switch level {
        case .buy: return "Teď je dobrá chvíle koupit"
        case .wait: return "Vyplatí se počkat"
        case .neutral: return "Cena je stabilní"
        }
    }

    var color: Color {
        switch level {
        case .buy: return .ponkGreen
        case .wait: return .ponkRedDeep
        case .neutral: return .ponkInk
        }
    }

    var symbol: String {
        switch level {
        case .buy: return "checkmark.seal.fill"
        case .wait: return "hourglass"
        case .neutral: return "equal.circle.fill"
        }
    }

    /// Sezónní zboží: měsíce, kdy bývá nejdražší (hlavní sezóna) a kdy se doprodává.
    private struct Season {
        let keys: [String]
        let peak: Set<Int>
        let cheap: Set<Int>
        let cheapText: String
    }

    private static let seasons: [Season] = [
        Season(keys: ["grilov", "zahradní nábytek", "bazén", "vířivk", "slunečník", "markýz", "ochrana proti slunci",
                      "vodní radovánky", "lounge", "lehátk", "houpačk", "klouzačk", "zahradní kuchyně"],
               peak: [4, 5, 6, 7], cheap: [8, 9, 10], cheapText: "v srpnu až říjnu"),
        Season(keys: ["sekačk", "křovinořez", "vyžínač", "zavlažov", "zahradní hadice", "čerpadl", "zahradní stroje",
                      "postřikovač", "provzdušňovač", "vertikutátor"],
               peak: [3, 4, 5, 6], cheap: [9, 10, 11], cheapText: "v září až listopadu"),
        Season(keys: ["vánoc", "advent"], peak: [11, 12], cheap: [1], cheapText: "po Vánocích"),
        Season(keys: ["velikono"], peak: [3, 4], cheap: [5], cheapText: "po Velikonocích"),
        Season(keys: ["kamna", "kouřovod", "topidl", "radiátor", "podlahové topení"],
               peak: [10, 11, 12, 1], cheap: [4, 5, 6, 7, 8], cheapText: "na jaře a v létě"),
        Season(keys: ["klimatizac", "ventilátor", "ochlazovač"], peak: [6, 7, 8], cheap: [9, 10, 11, 12, 1, 2],
               cheapText: "na podzim a v zimě"),
        Season(keys: ["sněh", "posypov"], peak: [11, 12, 1], cheap: [3, 4], cheapText: "na jaře"),
        Season(keys: ["vysavače listí", "fukar"], peak: [10, 11], cheap: [1, 2, 3], cheapText: "v zimě"),
    ]

    init(_ p: ProductDetail, today: Date = .now) {
        var buy: [String] = [], wait: [String] = [], info: [String] = []
        guard let price = p.price, p.active != 0 else {
            level = .neutral
            reasons = ["Produkt teď není v nabídce."]
            return
        }
        let history = p.history.filter { $0.price > 0 }
        let since = history.first.map { shortDay($0.day) } ?? shortDay(p.first_seen)

        if let d = p.real_discount, d > 0 {
            buy.append("Skutečná sleva \(d) % oproti nejnižší ceně za posledních 30 dní.")
        }
        if p.labels.contains("sell_off") {
            buy.append("Výprodej: zboží se už nedoplňuje, může brzy dojít.")
        }
        if let gift = p.promos?.first(where: { $0.kind == "gift" }) {
            buy.append("K nákupu je dárek\(gift.end.map { ", akce platí do \(shortDay($0))" } ?? "").")
        }
        let tracked = history.map(\.price) + [price]
        let distinct = Set(tracked.map { Int($0.rounded()) })
        if let low = tracked.min(), distinct.count > 1 {
            if price <= low + 0.5 {
                buy.append("Nejnižší cena od \(since), kdy ji Ponk sleduje.")
            } else if let when = history.last(where: { $0.price <= low + 0.5 }) {
                wait.append("Ponk ji viděl i za \(money(low)) Kč (\(shortDay(when.day))), teď je o \(money(price - low)) Kč dráž.")
            }
        }
        if let m = p.min30_price, price > m + 0.5, (p.real_discount ?? 0) == 0 {
            wait.append("Za posledních 30 dní byla za \(money(m)) Kč.")
        }
        var changes = 0
        for (a, b) in zip(history, history.dropFirst()) where abs(a.price - b.price) >= 1 { changes += 1 }
        if changes >= 3 {
            info.append("Cena se často mění (\(changes)× od \(since)). Nastav hlídání a Ponk dá vědět, až klesne.")
        }

        // sezónní výprodeje podle kategorie
        let cats = p.cat_path.joined(separator: " ").lowercased() + " " + p.name.lowercased()
        let month = Calendar.current.component(.month, from: today)
        if let s = Self.seasons.first(where: { s in s.keys.contains { cats.contains($0) } }) {
            if s.cheap.contains(month) {
                buy.append("Sezónní zboží: teď je období výprodejů.")
            } else if s.peak.contains(month) {
                wait.append("Sezónní zboží: obvykle zlevňuje \(s.cheapText).")
            } else {
                info.append("Sezónní zboží: nejlevnější bývá \(s.cheapText).")
            }
        }

        if buy.count > wait.count {
            level = .buy
        } else if wait.count > buy.count {
            level = .wait
        } else if buy.isEmpty {
            level = .neutral
            if distinct.count <= 1 { info.insert("Cena se od \(since) nezměnila, není důvod čekat.", at: 0) }
        } else {
            level = .neutral
        }
        reasons = buy + wait + info
    }
}

struct BuyAdviceCard: View {
    let advice: BuyAdvice
    let watched: Bool
    var onWatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(advice.title, systemImage: advice.symbol)
                .font(.ponk(18, .heavy, relativeTo: .headline))
                .foregroundStyle(advice.color)
            ForEach(advice.reasons, id: \.self) { r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Color.ponkMuted)
                    Text(r).font(.ponk(15)).foregroundStyle(Color.ponkInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if advice.level == .wait, !watched {
                Button(action: onWatch) {
                    Label("Hlídat cenu", systemImage: "eye").font(.ponk(15, .semibold))
                }
                .ponkGlassButton()
                .padding(.top, 2)
            }
            Text("Odhad z historie cen a obvyklých sezónních výprodejů, ne záruka.")
                .font(.ponk(12, relativeTo: .caption2))
                .foregroundStyle(Color.ponkMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(advice.color.opacity(advice.level == .neutral ? 0.15 : 0.45)))
    }
}
