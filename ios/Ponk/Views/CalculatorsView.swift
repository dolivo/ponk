import SwiftUI

/// Kalkulačky materiálu: barva, dlažba a obklad, sádrokarton, beton. Výsledek jde přidat do
/// nákupního seznamu a každou položku dohledat v katalogu. Spotřeby jsou orientační a dají se
/// přepsat podle údajů na obalu konkrétního výrobku.
enum Calc: String, CaseIterable, Identifiable {
    case paint, tiles, drywall, concrete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paint: return "Malování"
        case .tiles: return "Dlažba a obklad"
        case .drywall: return "Sádrokartonová příčka"
        case .concrete: return "Beton"
        }
    }

    var subtitle: String {
        switch self {
        case .paint: return "Barva na stěny a strop, páska, fólie"
        case .tiles: return "Krabice dlažby, lepidlo, spárovačka"
        case .drywall: return "Desky, profily, šrouby, tmel, izolace"
        case .concrete: return "Deska nebo patky pod sloupky"
        }
    }

    var icon: String {
        switch self {
        case .paint: return "paintbrush.pointed.fill"
        case .tiles: return "square.grid.3x3.fill"
        case .drywall: return "rectangle.split.3x1.fill"
        case .concrete: return "shippingbox.fill"
        }
    }

    struct Field: Identifiable {
        let id: String
        let label: String
        let unit: String
        let value: Double
        var toggle = false
        var section = 0  // 0 = rozměry, 1 = spotřeba (dá se přepsat)
    }

    var fields: [Field] {
        switch self {
        case .paint:
            return [
                Field(id: "l", label: "Délka místnosti", unit: "m", value: 4),
                Field(id: "w", label: "Šířka místnosti", unit: "m", value: 3),
                Field(id: "h", label: "Výška stěn", unit: "m", value: 2.6),
                Field(id: "open", label: "Okna a dveře", unit: "m²", value: 4),
                Field(id: "ceiling", label: "Malovat i strop", unit: "", value: 1, toggle: true),
                Field(id: "coats", label: "Počet vrstev", unit: "×", value: 2, section: 1),
                Field(id: "cover", label: "Vydatnost barvy", unit: "m²/l", value: 7, section: 1),
            ]
        case .tiles:
            return [
                Field(id: "area", label: "Plocha", unit: "m²", value: 10),
                Field(id: "waste", label: "Prořez", unit: "%", value: 10),
                Field(id: "box", label: "Balení dlažby", unit: "m²/krabice", value: 1.44, section: 1),
                Field(id: "glue", label: "Spotřeba lepidla", unit: "kg/m²", value: 4, section: 1),
                Field(id: "grout", label: "Spotřeba spárovačky", unit: "kg/m²", value: 0.4, section: 1),
            ]
        case .drywall:
            return [
                Field(id: "l", label: "Délka příčky", unit: "m", value: 4),
                Field(id: "h", label: "Výška příčky", unit: "m", value: 2.6),
                Field(id: "both", label: "Opláštění z obou stran", unit: "", value: 1, toggle: true),
                Field(id: "wool", label: "Izolace uvnitř", unit: "", value: 1, toggle: true),
                Field(id: "board", label: "Velikost desky", unit: "m²", value: 2.5, section: 1),
                Field(id: "spacing", label: "Rozteč CW profilů", unit: "cm", value: 62.5, section: 1),
            ]
        case .concrete:
            return [
                Field(id: "sl", label: "Deska: délka", unit: "m", value: 3),
                Field(id: "sw", label: "Deska: šířka", unit: "m", value: 2),
                Field(id: "st", label: "Deska: tloušťka", unit: "cm", value: 10),
                Field(id: "pn", label: "Patky: počet", unit: "ks", value: 0),
                Field(id: "ps", label: "Patky: strana", unit: "cm", value: 30),
                Field(id: "pd", label: "Patky: hloubka", unit: "cm", value: 80),
                Field(id: "bag", label: "Výtěžnost pytle směsi 25 kg", unit: "l", value: 12, section: 1),
            ]
        }
    }

    struct Line: Identifiable {
        let title: String
        let amount: String
        let search: String
        var note: String? = nil
        var id: String { title }
    }

    func compute(_ v: [String: Double]) -> (summary: String, lines: [Line]) {
        func x(_ k: String) -> Double { max(0, v[k] ?? 0) }
        func up(_ d: Double) -> Int { Int(ceil(d - 1e-9)) }
        func num(_ d: Double, _ digits: Int = 1) -> String {
            d.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "cs_CZ")))
        }
        switch self {
        case .paint:
            let walls = max(0, 2 * (x("l") + x("w")) * x("h") - x("open"))
            let ceiling = x("ceiling") > 0 ? x("l") * x("w") : 0
            let area = walls + ceiling
            let litres = x("cover") > 0 ? area * max(1, x("coats")) / x("cover") * 1.1 : 0
            let perimeter = 2 * (x("l") + x("w"))
            return ("Plocha k malování \(num(area)) m²", [
                Line(title: "Malířská barva", amount: "\(num(litres)) l", search: "malířská barva",
                     note: "včetně 10 % rezervy, \(num(max(1, x("coats")), 0)) vrstvy"),
                Line(title: "Malířská páska", amount: "\(up(perimeter * (ceiling > 0 ? 2 : 1) / 50)) role (50 m)", search: "malířská páska",
                     note: "podél stropu\(ceiling > 0 ? " a podlahy" : " a podlahy")"),
                Line(title: "Zakrývací fólie", amount: "\(up(x("l") * x("w") / 20)) ks (4×5 m)", search: "zakrývací fólie"),
            ])
        case .tiles:
            let area = x("area") * (1 + x("waste") / 100)
            let boxes = x("box") > 0 ? up(area / x("box")) : 0
            let glue = x("area") * x("glue")
            let grout = x("area") * x("grout")
            return ("S prořezem \(num(area)) m²", [
                Line(title: "Dlažba / obklad", amount: "\(boxes) krabic (\(num(Double(boxes) * x("box"), 2)) m²)", search: "dlažba"),
                Line(title: "Lepidlo na obklady", amount: "\(up(glue / 25)) pytlů 25 kg", search: "lepidlo na obklady a dlažbu",
                     note: "\(num(glue)) kg"),
                Line(title: "Spárovací hmota", amount: "\(up(grout / 5)) balení 5 kg", search: "spárovací hmota", note: "\(num(grout)) kg"),
            ])
        case .drywall:
            let sides = x("both") > 0 ? 2.0 : 1.0
            let area = x("l") * x("h")
            let boards = x("board") > 0 ? up(area * sides * 1.1 / x("board")) : 0
            let cw = x("spacing") > 0 ? up(x("l") / (x("spacing") / 100)) + 1 : 0
            let uw = up(2 * x("l") / 4)
            var lines = [
                Line(title: "Sádrokartonová deska", amount: "\(boards) ks", search: "sádrokartonová deska",
                     note: "\(num(area * sides)) m² + 10 % prořez"),
                Line(title: "CW profil", amount: "\(cw) ks (délka ≥ \(num(x("h"))) m)", search: "CW profil"),
                Line(title: "UW profil", amount: "\(uw) ks po 4 m", search: "UW profil", note: "podlaha a strop"),
                Line(title: "Šrouby do sádrokartonu", amount: "\(up(area * sides * 20 / 1000)) balení 1000 ks", search: "šrouby do sádrokartonu",
                     note: "asi \(up(area * sides * 20)) ks"),
                Line(title: "Spárovací tmel", amount: "\(up(area * sides * 0.4 / 5)) pytlů 5 kg", search: "tmel na sádrokarton"),
                Line(title: "Výztužná páska", amount: "\(up(area * sides * 1.4 / 25)) role (25 m)", search: "výztužná páska sádrokarton"),
                Line(title: "Těsnicí páska pod profily", amount: "\(up((2 * x("l") + 2 * x("h")) / 30)) role (30 m)", search: "těsnicí páska profil"),
            ]
            if x("wool") > 0 {
                lines.append(Line(title: "Minerální izolace", amount: "\(num(area)) m²", search: "minerální izolace příčky"))
            }
            return ("Příčka \(num(area)) m², \(sides > 1 ? "oboustranně" : "jednostranně")", lines)
        case .concrete:
            let slab = x("sl") * x("sw") * x("st") / 100
            let pads = x("pn") * pow(x("ps") / 100, 2) * x("pd") / 100
            let vol = slab + pads
            let bags = x("bag") > 0 ? up(vol * 1000 * 1.05 / x("bag")) : 0
            return ("Objem betonu \(num(vol, 2)) m³", [
                Line(title: "Betonová směs 25 kg", amount: "\(bags) pytlů", search: "betonová směs",
                     note: "hotová suchá směs, +5 % rezerva"),
                Line(title: "nebo Cement 25 kg", amount: "\(up(vol * 300 / 25)) pytlů", search: "cement",
                     note: "míchání z cementu (asi 300 kg/m³)"),
                Line(title: "a Štěrkopísek", amount: "\(num(vol * 1.9)) t", search: "štěrkopísek", note: "k cementu"),
            ])
        }
    }
}

/// Seznam kalkulaček.
struct CalculatorsView: View {
    var body: some View {
        List {
            Section {
                ForEach(Calc.allCases) { c in
                    NavigationLink {
                        CalculatorView(calc: c)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: c.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.ponkRed)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.ponk(17, .semibold))
                                Text(c.subtitle).font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Výpočty jsou orientační. Spotřebu najdeš na obalu výrobku a v kalkulačce ji můžeš přepsat.")
            }
        }
        .navigationTitle("Kalkulačky")
    }
}

/// Jedna kalkulačka: rozměry, spotřeba, výsledek a přidání do nákupního seznamu.
struct CalculatorView: View {
    let calc: Calc
    @Environment(AppModel.self) private var app
    @AppStorage("currentList") private var currentList = 0
    @State private var values: [String: Double] = [:]
    @State private var added = 0
    @State private var toast: String?

    var body: some View {
        let result = calc.compute(values)
        Form {
            Section("Rozměry") { ForEach(calc.fields.filter { $0.section == 0 }) { field($0) } }
            Section {
                ForEach(calc.fields.filter { $0.section == 1 }) { field($0) }
            } header: {
                Text("Spotřeba a balení")
            } footer: {
                Text("Podle obalu konkrétního výrobku.")
            }
            Section {
                ForEach(result.lines) { line in
                    NavigationLink(value: ResultsRoute(query: ["q": line.search], title: line.title)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(line.title).font(.ponk(16, .semibold))
                                Spacer()
                                Text(line.amount).font(.ponk(16, .heavy)).monospacedDigit()
                            }
                            if let n = line.note { Text(n).font(.ponk(13)).foregroundStyle(Color.ponkMuted) }
                        }
                    }
                }
                Button {
                    Task { await addAll(result.lines) }
                } label: {
                    Label("Přidat do nákupního seznamu", systemImage: "cart.badge.plus").font(.ponk(16, .semibold))
                }
            } header: {
                Text(result.summary)
            } footer: {
                Text("Klepnutím na položku ji najdeš v katalogu. Do seznamu se přidá jako vlastní položka s množstvím.")
            }
        }
        .navigationTitle(calc.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: added)
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.ponk(15, .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .ponkGlassCapsule(tint: Color.ponkGreen.opacity(0.3))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            if values.isEmpty { values = Dictionary(uniqueKeysWithValues: calc.fields.map { ($0.id, $0.value) }) }
        }
    }

    @ViewBuilder
    private func field(_ f: Calc.Field) -> some View {
        if f.toggle {
            Toggle(f.label, isOn: Binding(get: { (values[f.id] ?? f.value) > 0 }, set: { values[f.id] = $0 ? 1 : 0 }))
                .tint(Color.ponkRed)
        } else {
            HStack {
                Text(f.label)
                Spacer()
                TextField("0", value: Binding(get: { values[f.id] ?? f.value }, set: { values[f.id] = $0 }),
                          format: .number.locale(Locale(identifier: "cs_CZ")))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .font(.ponk(17, .semibold))
                Text(f.unit).foregroundStyle(Color.ponkMuted).frame(minWidth: 30, alignment: .leading)
            }
        }
    }

    private func addAll(_ lines: [Calc.Line]) async {
        var id = currentList
        let lists = (try? await app.api.get("lists", as: ListResponse<ShoppingListInfo>.self).items) ?? []
        if !lists.contains(where: { $0.id == id }) { id = lists.first?.id ?? 1 }
        for l in lines {
            try? await app.api.send("POST", "list/\(id)", body: ["text": "\(l.title): \(l.amount)", "qty": 1])
        }
        currentList = id
        added += 1
        withAnimation(.snappy) { toast = "Přidáno do seznamu" }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.snappy) { toast = nil }
    }
}
