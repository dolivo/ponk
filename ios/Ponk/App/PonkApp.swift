import SwiftUI

@main
struct PonkApp: App {
    @State private var app = AppModel()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("font") private var font = PonkFont.barlow.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(.ponkRed)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .id(font) // po změně písma se rozhraní překreslí
        }
    }
}

enum AppTab: Hashable {
    case home, sale, watch, more, search
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("server") private var server = ""
    @State private var tab: AppTab = .home
    @State private var showSetup = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Domů", systemImage: "house", value: AppTab.home) {
                NavigationStack { HomeView().ponkDestinations() }
            }
            Tab("Výprodej", systemImage: "tag", value: AppTab.sale) {
                NavigationStack {
                    ResultsView(route: ResultsRoute(query: ["label": "sell_off", "sort": "discount"], title: "Výprodej"))
                        .ponkDestinations()
                }
            }
            Tab("Hlídané", systemImage: "eye", value: AppTab.watch) {
                NavigationStack { WatchView().ponkDestinations() }
            }
            .badge(app.meta?.watched_drops ?? 0)
            Tab("Více", systemImage: "line.3.horizontal", value: AppTab.more) {
                NavigationStack { MoreView() }
            }
            // V iOS 26 se hledání zobrazí jako samostatné skleněné tlačítko vedle lišty.
            Tab(value: AppTab.search, role: .search) {
                SearchTab()
            }
        }
        .ponkMinimizingTabBar()
        .task {
            if server.isEmpty { showSetup = true } else { await app.loadMeta() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !server.isEmpty { Task { await app.loadMeta() } }
        }
        .sheet(isPresented: $showSetup) {
            ServerSetupView { showSetup = false }
                .interactiveDismissDisabled(server.isEmpty)
        }
    }
}

/// První spuštění: adresa serveru, kterou vypíše `python run.py` na počítači.
struct ServerSetupView: View {
    var onDone: () -> Void
    @Environment(AppModel.self) private var app
    @AppStorage("server") private var server = ""
    @State private var address = ""
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.20:8765", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.ponk(20, .semibold))
                } header: {
                    Text("Adresa serveru")
                } footer: {
                    Text("Na počítači spusť python run.py. Adresu najdeš na řádku „v mobilu (Wi-Fi)“. Telefon musí být ve stejné Wi-Fi síti.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ponkRedDeep) }
                }
            }
            .navigationTitle("Připojení")
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await connect() }
                } label: {
                    Text(testing ? "Zkouším spojení…" : "Připojit").font(.ponk(18, .heavy)).frame(maxWidth: .infinity)
                }
                .ponkProminentButton()
                .controlSize(.large)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                .padding()
            }
            .onAppear { address = server }
        }
    }

    private func connect() async {
        testing = true
        defer { testing = false }
        do {
            _ = try await app.api.test(server: address)
            server = address.trimmingCharacters(in: .whitespacesAndNewlines)
            await app.loadMeta()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
