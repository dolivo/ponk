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
        // Ranní kontrola na pozadí: stáhne nová data z GitHubu a upozorní na zlevněné hlídané produkty.
        .backgroundTask(.appRefresh(DataStore.refreshTaskID)) {
            await DataStore.shared.backgroundRefresh()
        }
    }
}

enum AppTab: Hashable {
    case home, sale, watch, more, search
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var started = false
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
            await DataStore.shared.start()
            started = true
            if DataStore.shared.hasData {
                await app.loadMeta()
                if await DataStore.shared.update(force: false) { await app.loadMeta() }
            } else {
                showSetup = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, started, DataStore.shared.hasData {
                Task {
                    if await DataStore.shared.update(force: false) { await app.loadMeta() }
                }
            }
            if phase == .background { DataStore.scheduleBackgroundRefresh() }
        }
        .sheet(isPresented: $showSetup) {
            DataSetupView { showSetup = false; Task { await app.loadMeta() } }
                .interactiveDismissDisabled(!DataStore.shared.hasData)
        }
    }
}

/// První spuštění: stažení dat, která každé ráno připravuje GitHub.
struct DataSetupView: View {
    var onDone: () -> Void
    @State private var store = DataStore.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ponk potřebuje stáhnout katalog Bauhausu s cenami a sklady. Je to asi 5 MB a další dny se data stahují sama, nejlépe na Wi-Fi.")
                    .font(.ponk(17))
                Text("Data připravuje každé ráno GitHub. Počítač ani server nepotřebuješ, hlídané produkty zůstávají jen v telefonu.")
                    .font(.ponk(15))
                    .foregroundStyle(Color.ponkMuted)
                if store.running {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.phase).font(.ponk(16, .semibold))
                        ProgressView().tint(.ponkRed)
                    }
                } else if !store.message.isEmpty, !store.hasData {
                    Label(store.message, systemImage: "exclamationmark.triangle")
                        .font(.ponk(15)).foregroundStyle(Color.ponkRedDeep)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Vítej v Ponku")
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        await store.update(force: true)
                        if store.hasData { onDone() }
                    }
                } label: {
                    Text(store.running ? "Stahuji…" : "Stáhnout data").font(.ponk(18, .heavy)).frame(maxWidth: .infinity)
                }
                .ponkProminentButton()
                .controlSize(.large)
                .disabled(store.running)
                .padding()
            }
        }
    }
}
