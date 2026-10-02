import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("server") private var server = ""
    @AppStorage("theme") private var theme = "system"
    @AppStorage("font") private var font = PonkFont.barlow.rawValue
    @State private var showServer = false
    @State private var syncTime = Date()
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                SyncCard().listRowInsets(EdgeInsets())
            }

            Section("Server") {
                Button { showServer = true } label: {
                    LabeledContent("Adresa", value: server.isEmpty ? "nenastaveno" : server)
                }
                .foregroundStyle(Color.ponkInk)
                if let error = app.metaError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ponkRedDeep).font(.ponk(15))
                } else if let meta = app.meta {
                    LabeledContent("Produktů v databázi", value: money(Double(meta.products)))
                }
            }

            if let meta = app.meta {
                Section {
                    Picker("Moje prodejna", selection: Binding(
                        get: { meta.settings["store"] ?? "888" },
                        set: { v in Task { await save(["store": v]) } })) {
                        ForEach(meta.stores) { Text($0.name).tag($0.code) }
                    }
                    DatePicker("Denní kontrola cen", selection: $syncTime, displayedComponents: .hourAndMinute)
                        .onChange(of: syncTime) { _, new in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: new)
                            let value = String(format: "%02d:%02d", c.hour ?? 6, c.minute ?? 0)
                            if value != meta.settings["sync_time"] { Task { await save(["sync_time": value]) } }
                        }
                    Toggle("Stahovat skladovost na prodejnách", isOn: Binding(
                        get: { meta.settings["sync_stock"] != "0" },
                        set: { v in Task { await save(["sync_stock": v ? "1" : "0"]) } }))
                } header: {
                    Text("Kontrola cen")
                } footer: {
                    Text("Kontrola běží na počítači, který musí být zapnutý. Když v nastavený čas neběží, proběhne hned po zapnutí. Celý katalog trvá zhruba 30–40 minut.")
                }
                .onAppear { syncTime = timeFrom(meta.settings["sync_time"]) }
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
                Text("Ponk je neoficiální open-source klient pro veřejně dostupná data z bauhaus.cz. Není nijak spojený se společností BAUHAUS. Názvy, ceny a obrázky patří jejich vlastníkům. Licence MIT.")
                    .font(.ponk(14)).foregroundStyle(Color.ponkMuted)
            }
        }
        .font(.ponk(17))
        .navigationTitle("Více")
        .refreshable { await app.loadMeta() }
        .sheet(isPresented: $showServer) {
            ServerSetupView { showServer = false }
        }
    }

    private func save(_ values: [String: String]) async {
        saving = true
        defer { saving = false }
        try? await app.api.send("POST", "settings", body: values)
        await app.loadMeta()
    }

    private func timeFrom(_ s: String?) -> Date {
        let parts = (s ?? "06:00").split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 6, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
    }
}
