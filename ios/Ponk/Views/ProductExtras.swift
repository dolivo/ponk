import SwiftUI
import UIKit

// Doplňky detailu produktu z webu Bauhausu: akce výrobců (dárky, cashback, soutěže),
// množstevní ceny, štítky (záruka, montáž, půjčovna…), obsah balení, dokumenty,
// výrobce a bezpečnostní informace.

/// Karty akcí. Dárek k nákupu je nahoře a nejvýraznější.
struct PromoCards: View {
    let promos: [Promo]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(promos) { PromoCard(promo: $0) }
        }
    }
}

struct PromoCard: View {
    let promo: Promo
    @Environment(\.openURL) private var openURL

    private var background: Color {
        Color(uiColor: UIColor(hex: Self.hex(promo.background) ?? 0x333333))
    }

    /// Text tmavý na světlém podkladu (např. žlutá Ryobi), jinak bílý.
    private var ink: Color {
        let v = Self.hex(promo.background) ?? 0x333333
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 160 ? Color(uiColor: UIColor(hex: 0x1A1A1A)) : .white
    }

    static func hex(_ s: String?) -> UInt32? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        return UInt32(t, radix: 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: promo.symbol).font(.system(size: 18, weight: .semibold))
                Text(promo.kindTitle).font(.ponk(17, .heavy, relativeTo: .headline))
                if let v = promo.value, promo.kind == "gift" {
                    Text("v hodnotě \(money(Double(v))) Kč")
                        .font(.ponk(14, .semibold, relativeTo: .subheadline))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            if let g = promo.gift, promo.kind == "gift" {
                Text("Zdarma získáte \(g)")
                    .font(.ponk(18, .heavy, relativeTo: .title3))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(promo.text)
                .font(.ponk(14, relativeTo: .footnote))
                .opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if promo.storeOnly { tag("Jen na prodejně", "storefront.fill") }
                if let end = promo.end { tag("Do \(shortDay(end)) \(String(end.prefix(4)))", "calendar") }
                Spacer(minLength: 0)
                if let link = promo.link, let url = URL(string: link) {
                    Button { openURL(url) } label: {
                        Label("Podmínky", systemImage: "arrow.up.right").font(.ponk(14, .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(ink)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func tag(_ t: String, _ symbol: String) -> some View {
        Label(t, systemImage: symbol)
            .font(.ponk(13, .semibold, relativeTo: .caption))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ink.opacity(0.14), in: Capsule())
    }
}

/// Množstevní sleva: cena za kus při odběru většího množství.
struct TierPrices: View {
    let tiers: [TierPrice]
    let price: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Množstevní sleva", systemImage: "square.stack.3d.up.fill")
                .font(.ponk(16, .heavy, relativeTo: .headline))
            ForEach(tiers, id: \.self) { t in
                HStack {
                    Text("od \(t.qty) ks").font(.ponk(15))
                    Spacer()
                    Text("\(money2(t.price)) Kč/ks").font(.ponk(15, .heavy)).monospacedDigit()
                    if let p = price, p > t.price {
                        Text("−\(Int(((p - t.price) / p * 100).rounded())) %")
                            .font(.ponk(13, .heavy))
                            .foregroundStyle(Color.ponkGreen)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ponkLine))
    }
}

/// Štítky služeb: prodloužená záruka, exkluzivita, montážní servis, půjčovna, energetická třída.
struct ProductBadges: View {
    let p: ProductDetail

    private var items: [(String, String)] {
        var out: [(String, String)] = []
        if let w = p.warranty { out.append(("Prodloužená záruka BAUHAUS \(w)", "checkmark.shield.fill")) }
        if p.exclusive == true { out.append(("Exkluzivně v BAUHAUS", "star.fill")) }
        if p.assembly == true { out.append(("Montážní servis", "wrench.and.screwdriver.fill")) }
        if p.rental == true { out.append(("Jde i půjčit v půjčovně", "arrow.triangle.2.circlepath")) }
        if let e = p.energy { out.append(("Energetická třída \(e)", "bolt.fill")) }
        return out
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.0) { t, symbol in
                    Label(t, systemImage: symbol)
                        .font(.ponk(15, .semibold))
                        .foregroundStyle(Color.ponkInk)
                }
            }
        }
    }
}

/// Obsah balení („1× aku šroubovák; 1× oboustranný bit“).
struct BoxContents: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "shippingbox").font(.system(size: 12)).foregroundStyle(Color.ponkMuted)
                    Text(line).font(.ponk(16))
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// Návody, technické a bezpečnostní listy (PDF).
struct DocumentList: View {
    let docs: [ProductDocument]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(docs.enumerated()), id: \.offset) { _, d in
                if let url = URL(string: d.url) {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.richtext.fill").foregroundStyle(Color.ponkRed)
                            Text(d.name).font(.ponk(16, .semibold)).foregroundStyle(Color.ponkInk)
                            Spacer()
                            Text("PDF").font(.ponk(13, .semibold)).foregroundStyle(Color.ponkMuted)
                            Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(Color.ponkMuted)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Color.ponkLine).frame(height: 1) }
                }
            }
        }
    }
}

/// Výrobce (povinné údaje dle nařízení o bezpečnosti výrobků) a varování u chemie.
struct ProducerSafety: View {
    let producer: Producer?
    let safety: [String: [String]]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = safety, !s.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                        Text(s["ghssignalword"]?.first ?? "Bezpečnostní upozornění").font(.ponk(16, .heavy))
                        if let pict = s["ghspictogram"] { Text(pict.joined(separator: ", ")).font(.ponk(13)).foregroundStyle(Color.ponkMuted) }
                    }
                    ForEach((s["hazardstatements"] ?? []) + (s["euhazardstatements"] ?? []), id: \.self) { Text($0).font(.ponk(14)) }
                    if let pre = s["precautionarystatements"], !pre.isEmpty {
                        DisclosureGroup("Pokyny pro bezpečné zacházení (\(pre.count))") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(pre, id: \.self) { Text($0).font(.ponk(14)) }
                            }
                            .padding(.top, 4)
                        }
                        .font(.ponk(14, .semibold))
                        .tint(Color.ponkInk)
                    }
                }
            }
            if let p = producer {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Výrobce / dovozce").font(.ponk(13)).foregroundStyle(Color.ponkMuted)
                    Text(p.name).font(.ponk(16, .semibold))
                    if let a = p.address { Text(a).font(.ponk(14)) }
                    if let e = p.email, let url = URL(string: "mailto:\(e)") {
                        Link(e, destination: url).font(.ponk(14)).tint(Color.ponkRedDeep)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }
}
