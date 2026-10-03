import SwiftUI

/// Filtry se projevují hned (výsledky pod listem se načítají živě), tlačítko dole ukazuje počet.
struct FiltersSheet: View {
    @Binding var query: Query
    let facets: Facets?
    let total: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let f = facets {
                    categorySection(f)

                    Section("Dostupnost") {
                        Toggle("Skladem na prodejně \(app.storeName(app.myStore))", isOn: flag("store", on: app.myStore ?? "888"))
                        Toggle("Skladem v e-shopu", isOn: flag("online"))
                    }

                    Section("Cena") {
                        HStack {
                            TextField("od \(money(f.price.min))", text: digits("pmin")).keyboardType(.numberPad)
                            Text("–").foregroundStyle(Color.ponkMuted)
                            TextField("do \(money(f.price.max))", text: digits("pmax")).keyboardType(.numberPad)
                            Text("Kč").foregroundStyle(Color.ponkMuted)
                        }
                    }

                    Section {
                        Picker("Skutečná sleva", selection: field("disc")) {
                            Text("Jakákoli").tag("")
                            ForEach(["10", "20", "30", "50", "70"], id: \.self) { Text("\($0) % a víc").tag($0) }
                        }
                        Picker("Zlevněno za posledních", selection: field("drop_days")) {
                            Text("Kdykoli").tag("")
                            Text("1 den").tag("1")
                            Text("7 dní").tag("7")
                            Text("30 dní").tag("30")
                        }
                        Picker("Nově naskladněno", selection: field("restock_days")) {
                            Text("Kdykoli").tag("")
                            Text("od včera").tag("1")
                            Text("za 3 dny").tag("3")
                            Text("za 7 dní").tag("7")
                        }
                        Picker("Nově v nabídce", selection: field("new_days")) {
                            Text("Kdykoli").tag("")
                            Text("za 7 dní").tag("7")
                            Text("za 14 dní").tag("14")
                            Text("za 30 dní").tag("30")
                        }
                    } footer: {
                        Text("Skutečná sleva se počítá proti nejnižší ceně za posledních 30 dní, ne proti „původní“ ceně.")
                    }

                    if !f.labels.isEmpty {
                        Section("Nabídka") {
                            ForEach(f.labels) { l in
                                Toggle(isOn: multi("label", l.value)) {
                                    LabeledContent(l.label, value: money(Double(l.count)))
                                }
                            }
                        }
                    }

                    if !f.brands.isEmpty {
                        Section {
                            NavigationLink {
                                MultiSelectList(title: "Značka", values: f.brands, selection: multiSet("brand"))
                            } label: {
                                LabeledContent("Značka", value: summary("brand"))
                            }
                        }
                    }

                    Section {
                        Picker("Hodnocení", selection: field("rating")) {
                            Text("Jakékoli").tag("")
                            Text("★★★★ a víc").tag("4")
                            Text("★★★ a víc").tag("3")
                        }
                        Toggle("Jen s cenou za jednotku", isOn: flag("unit"))
                    }

                    if !f.attrs.isEmpty {
                        Section("Parametry") {
                            ForEach(f.attrs) { a in
                                NavigationLink {
                                    MultiSelectList(title: a.label, values: a.values, selection: multiSet("a_" + a.code))
                                } label: {
                                    LabeledContent(a.label, value: summary("a_" + a.code))
                                }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .font(.ponk(17))
            .navigationTitle("Filtry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit vše") {
                        query = query.filter { ["q", "sort"].contains($0.key) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text("Zobrazit \(money(Double(total))) \(plural(total, "produkt", "produkty", "produktů"))")
                        .font(.ponk(18, .heavy))
                        .frame(maxWidth: .infinity)
                }
                .ponkProminentButton()
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func categorySection(_ f: Facets) -> some View {
        let level = f.categories.level
        let values = f.categories.values.filter { $0.value != query[level] }
        if !values.isEmpty || query["cat1"] != nil {
            Section("Kategorie") {
                if query["cat1"] != nil {
                    Button {
                        if query["cat3"] != nil { query["cat3"] = nil }
                        else if query["cat2"] != nil { query["cat2"] = nil }
                        else { query["cat1"] = nil }
                    } label: {
                        Label(query["cat3"] != nil ? (query["cat2"] ?? "") : query["cat2"] != nil ? (query["cat1"] ?? "") : "Všechny kategorie",
                              systemImage: "chevron.left")
                    }
                }
                ForEach(values.prefix(30)) { c in
                    Button {
                        query[level] = c.value
                    } label: {
                        LabeledContent(c.value, value: money(Double(c.count)))
                    }
                    .foregroundStyle(Color.ponkInk)
                }
            }
        }
    }

    // --- vazby na parametry hledání ---------------------------------------

    private func field(_ key: String) -> Binding<String> {
        Binding(get: { query[key] ?? "" }, set: { query[key] = $0.isEmpty ? nil : $0 })
    }

    private func digits(_ key: String) -> Binding<String> {
        Binding(get: { query[key] ?? "" }, set: { v in
            let d = v.filter(\.isNumber)
            query[key] = d.isEmpty ? nil : d
        })
    }

    private func flag(_ key: String, on: String = "1") -> Binding<Bool> {
        Binding(get: { query[key] != nil }, set: { query[key] = $0 ? on : nil })
    }

    private func multiSet(_ key: String) -> Binding<Set<String>> {
        Binding(get: { Set((query[key] ?? "").split(separator: "|").map(String.init)) },
                set: { s in query[key] = s.isEmpty ? nil : s.sorted().joined(separator: "|") })
    }

    private func multi(_ key: String, _ value: String) -> Binding<Bool> {
        let set = multiSet(key)
        return Binding(get: { set.wrappedValue.contains(value) }, set: { on in
            var s = set.wrappedValue
            if on { s.insert(value) } else { s.remove(value) }
            set.wrappedValue = s
        })
    }

    private func summary(_ key: String) -> String {
        let v = (query[key] ?? "").split(separator: "|")
        if v.isEmpty { return "Vše" }
        return v.count == 1 ? String(v[0]) : "\(v.count) vybrané"
    }
}

struct MultiSelectList: View {
    let title: String
    let values: [FacetValue]
    @Binding var selection: Set<String>
    @State private var search = ""

    var body: some View {
        List {
            ForEach(values.filter { search.isEmpty || $0.value.localizedCaseInsensitiveContains(search) }) { v in
                Button {
                    if selection.contains(v.value) { selection.remove(v.value) } else { selection.insert(v.value) }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(v.value) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selection.contains(v.value) ? Color.ponkRed : Color.ponkMuted)
                        Text(v.value).foregroundStyle(Color.ponkInk)
                        Spacer()
                        Text(money(Double(v.count))).foregroundStyle(Color.ponkMuted)
                    }
                    .font(.ponk(17))
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Najít")
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Zrušit výběr") { selection = [] } }
            }
        }
    }
}
