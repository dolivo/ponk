import SwiftUI

/// Klíč nastavení: vybrané akumulátorové platformy oddělené „|“ (stejně jako filtr katalogu).
enum MyPlatforms {
    static let key = "myPlatforms"
    static func list(_ raw: String) -> [String] { raw.split(separator: "|").map(String.init) }
}

/// Výběr akumulátorových platforem, které mám doma. Katalog pak umí ukázat jen nářadí,
/// které k nim pasuje, a u nářadí se ukáže, kolik ušetřím za verzi bez akumulátoru.
struct PlatformsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(MyPlatforms.key) private var mine = ""
    @State private var options: [PlatformOption] = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                if options.isEmpty, loaded {
                    Text("Platformy přijdou s dalšími denními daty. Otevři aplikaci zítra ráno nebo stáhni data ve Více.")
                        .foregroundStyle(Color.ponkMuted)
                }
                ForEach(options) { o in
                    Toggle(isOn: Binding(get: { MyPlatforms.list(mine).contains(o.id) }, set: { on in
                        var l = MyPlatforms.list(mine).filter { $0 != o.id }
                        if on { l.append(o.id) }
                        mine = l.joined(separator: "|")
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.title).font(.ponk(17, .semibold))
                            Text("\(o.count) produktů").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                        }
                    }
                    .tint(Color.ponkRed)
                }
            } footer: {
                Text("V katalogu pak přibude rychlý filtr „K mým bateriím“ a „Bez akumulátoru“. V detailu nářadí uvidíš, jestli pasuje k tvým bateriím a kolik stojí verze bez akumulátoru.")
            }
        }
        .navigationTitle("Moje aku platformy")
        .task {
            options = (try? await app.api.get("platforms", as: ListResponse<PlatformOption>.self).items) ?? []
            loaded = true
        }
    }
}

/// Blok v detailu produktu: platforma, jestli pasuje k mým bateriím, a tělo × sada.
struct PlatformBlock: View {
    let platform: PlatformInfo
    let alternatives: [Item]
    let price: Double?
    @AppStorage(MyPlatforms.key) private var mine = ""

    private var isMine: Bool { MyPlatforms.list(mine).contains(platform.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "battery.100percent.bolt").foregroundStyle(isMine ? Color.ponkGreen : Color.ponkInk)
                VStack(alignment: .leading, spacing: 1) {
                    Text(platform.title).font(.ponk(16, .heavy))
                    if isMine {
                        Text(platform.body == 1 ? "Pasuje k tvým akumulátorům · bez akumulátoru" : "Pasuje k tvým akumulátorům")
                            .font(.ponk(14, .semibold)).foregroundStyle(Color.ponkGreen)
                    } else if platform.body == 1 {
                        Text("Bez akumulátoru a nabíječky").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                    } else if platform.body == 0 {
                        Text("S akumulátorem").font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            if !alternatives.isEmpty {
                Text(platform.body == 1 ? "Stejné nářadí s akumulátorem" : "Stejné nářadí bez akumulátoru (jen tělo)")
                    .font(.ponk(14, .semibold)).foregroundStyle(Color.ponkMuted)
                ForEach(alternatives) { alt in
                    NavigationLink(value: ProductRoute(sku: alt.sku)) {
                        HStack(spacing: 10) {
                            ProductImage(path: alt.image, w: 80, h: 99).frame(width: 34, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.name).font(.ponk(14)).lineLimit(1)
                                if let a = alt.price, let p = price {
                                    let diff = platform.body == 1 ? a - p : p - a
                                    if diff > 0 {
                                        Text(platform.body == 1 ? "akumulátor a nabíječka navíc za \(money(diff)) Kč"
                                                                : "ušetříš \(money(diff)) Kč, když už baterii máš")
                                            .font(.ponk(13, .semibold))
                                            .foregroundStyle(platform.body == 1 ? Color.ponkMuted : Color.ponkGreen)
                                    }
                                }
                            }
                            Spacer(minLength: 4)
                            Text("\(money(alt.price)) Kč").font(.ponk(15, .heavy)).monospacedDigit().lineLimit(1).fixedSize()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.ponkMuted)
                        }
                        .foregroundStyle(Color.ponkInk)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isMine ? Color.ponkGreen.opacity(0.6) : Color.ponkLine))
    }
}
