import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("theme") private var theme = "system"
    @AppStorage("font") private var font = PonkFont.barlow.rawValue
    @AppStorage("auto_wifi") private var autoWiFi = true
    @AppStorage("repo") private var repo = ""
    @AppStorage(Recents.searchesKey) private var recentSearches = ""
    @AppStorage(Recents.viewedKey) private var recentViewed = ""
    @State private var store = DataStore.shared

    var body: some View {
        Form {
            Section {
                SyncCard().listRowInsets(EdgeInsets())
            }

            Section {
                if let meta = app.meta {
                    LabeledContent("Produktů v datech", value: money(Double(meta.products)))
                    Picker("Moje prodejna", selection: Binding(
                        get: { meta.settings["store"] ?? "888" },
                        set: { v in Task { await save(["store": v]) } })) {
                        ForEach(meta.stores) { Text($0.name).tag($0.code) }
                    }
                }
                Toggle("Stahovat nová data jen na Wi-Fi", isOn: $autoWiFi)
            } header: {
                Text("Data")
            } footer: {
                Text("Ceny celého katalogu kontroluje každé ráno kolem 5:20 GitHub. Telefon si nová data stáhne sám po otevření aplikace nebo na pozadí (asi 5 MB). Detail produktu načítá aktuální cenu a sklad přímo z Bauhausu.")
            }

            Section {
                TextField(DataStore.defaultRepo, text: $repo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Zdroj dat na GitHubu")
            } footer: {
                Text("Repozitář, ve kterém běží denní kontrola cen (uživatel/repozitář). Nech prázdné pro výchozí \(DataStore.defaultRepo).")
            }

            Section("Vzhled") {
                Picker("Vzhled", selection: $theme) {
                    Text("Podle systému").tag("system")
                    Text("Světlý").tag("light")
                    Text("Tmavý").tag("dark")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section("Písmo") {
                ForEach(PonkFont.allCases) { f in
                    Button { font = f.rawValue } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Akumulátorový šroubovák").font(.ponk(21, .heavy, font: f))
                                Text(f.displayName).font(.system(size: 13)).foregroundStyle(Color.ponkMuted)
                            }
                            Spacer()
                            Text("1 290 Kč").font(.ponk(21, .heavy, font: f)).monospacedDigit()
                            if font == f.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(Color.ponkRed)
                            }
                        }
                        .foregroundStyle(Color.ponkInk)
                    }
                }
            }

            Section {
                Button("Vymazat historii hledání a prohlížení", role: .destructive) {
                    recentSearches = ""
                    recentViewed = ""
                }
                .disabled(recentSearches.isEmpty && recentViewed.isEmpty)
                Button("Uvolnit mezipaměť obrázků") {
                    ImageCache.shared.removeAll()
                    URLCache.shared.removeAllCachedResponses()
                }
            } header: {
                Text("Soukromí a místo")
            } footer: {
                Text("Obrázky se ukládají do mezipaměti, aby se regály posouvaly plynule. Po vymazání se znovu stáhnou ve stejné kvalitě.")
            }

            Section {
                BrandHeader().padding(.horizontal, -14).listRowBackground(Color.clear)
                Text("Ponk je neoficiální open-source klient pro veřejně dostupná data z bauhaus.cz. Není nijak spojený se společností BAUHAUS. Názvy, ceny a obrázky patří jejich vlastníkům. Licence MIT.")
                    .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
                LabeledContent("Verze aplikace", value: appVersion)
                if let d = store.generatedAt {
                    LabeledContent("Data připravena", value: d.formatted(.dateTime.day().month(.defaultDigits).hour().minute().locale(Locale(identifier: "cs_CZ"))))
                }
            }
        }
        .font(.ponk(17))
        .navigationTitle("Více")
        .refreshable { await app.loadMeta() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func save(_ values: [String: String]) async {
        try? await app.api.send("POST", "settings", body: values)
        await app.loadMeta()
    }
}
