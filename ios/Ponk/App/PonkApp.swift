import SwiftUI

@main
struct PonkApp: App {
    @State private var app = AppModel()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("font") private var font = PonkFont.barlow.rawValue
    @State private var showSplash = true

    init() {
        ImageCache.configureURLCache()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .id(font) // po změně písma se rozhraní překreslí
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
            .environment(app)
            .tint(.ponkRed)
            .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
        // Ranní kontrola na pozadí: stáhne nová data z GitHubu a upozorní na zlevněné hlídané produkty.
        .backgroundTask(.appRefresh(DataStore.refreshTaskID)) {
            await DataStore.shared.backgroundRefresh()
        }
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case catalog, home, watch, search, more
}

/// Kde je hlavní menu: svisle u pravého/levého okraje (ovládání palcem jedné ruky) nebo klasicky dole.
enum MenuSide: String, CaseIterable {
    case right, left, bottom
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// Poslední otevřená záložka se pamatuje i po zavření aplikace.
    @SceneStorage("tab") private var tab: AppTab = .catalog
    @AppStorage("menuSide") private var menuSide = MenuSide.right.rawValue
    @State private var started = false
    @State private var showSetup = false
    /// Záložky, které už byly otevřené (v bočním režimu zůstávají naživu, aby si držely stav).
    @State private var visited: Set<AppTab> = []
    /// Opětovné klepnutí na otevřenou záložku ji vrátí na začátek.
    @State private var resets: [AppTab: Int] = [:]

    private var side: MenuSide { MenuSide(rawValue: menuSide) ?? .right }

    var body: some View {
        Group {
            if side == .bottom { tabBarLayout } else { sideLayout }
        }
        .task {
            await DataStore.shared.start()
            started = true
            if DataStore.shared.hasData {
                await app.loadMeta()
                if await DataStore.shared.update(force: false) { await app.loadMeta() }
            } else {
                try? await Task.sleep(for: .seconds(1.5)) // až po úvodní animaci
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

    @ViewBuilder
    private func screen(_ t: AppTab) -> some View {
        switch t {
        case .catalog:
            // Hlavní stránka: všechny položky najednou s hledáním a filtry.
            NavigationStack {
                ResultsView(route: ResultsRoute(query: [:], title: "Katalog"), catalog: true)
                    .ponkDestinations()
            }
        case .home:
            NavigationStack { HomeView().ponkDestinations() }
        case .watch:
            // Nákupní seznamy a hlídané produkty
            NavigationStack { MyStuffView().ponkDestinations() }
        case .search:
            SearchTab()
        case .more:
            NavigationStack { MoreView() }
        }
    }

    /// Klasická spodní lišta (systémová, na iOS 26 Liquid Glass).
    private var tabBarLayout: some View {
        TabView(selection: $tab) {
            Tab("Katalog", systemImage: "square.grid.2x2", value: AppTab.catalog) { screen(.catalog) }
            Tab("Slevy", systemImage: "tag", value: AppTab.home) { screen(.home) }
            Tab("Seznam", systemImage: "checklist", value: AppTab.watch) { screen(.watch) }
                .badge(app.meta?.watched_drops ?? 0)
            Tab("Více", systemImage: "line.3.horizontal", value: AppTab.more) { screen(.more) }
            // V iOS 26 se hledání zobrazí jako samostatné skleněné tlačítko vedle lišty.
            Tab(value: AppTab.search, role: .search) { screen(.search) }
        }
        .ponkMinimizingTabBar()
    }

    /// Svislé menu u okraje obrazovky. Záložky se vytvoří při prvním otevření a pak zůstávají
    /// naživu (skryté), takže si drží rozscrollovaný seznam i otevřené detaily jako u spodní lišty.
    private var sideLayout: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                if visited.contains(t) || t == tab {
                    screen(t)
                        .id(resets[t, default: 0])
                        .opacity(t == tab ? 1 : 0)
                        .allowsHitTesting(t == tab)
                        .accessibilityHidden(t != tab)
                }
            }
        }
        .overlay(alignment: side == .left ? .bottomLeading : .bottomTrailing) {
            SideMenu(selection: $tab, badge: app.meta?.watched_drops ?? 0) { t in
                resets[t, default: 0] += 1
            }
            .padding(side == .left ? .leading : .trailing, 8)
            // nad plovoucími tlačítky Filtry / Řazení, v dosahu palce
            .padding(.bottom, 92)
            .ignoresSafeArea(.keyboard)
        }
        .onChange(of: tab, initial: true) { _, t in visited.insert(t) }
    }
}

/// Svislé skleněné menu pro ovládání jednou rukou.
struct SideMenu: View {
    @Binding var selection: AppTab
    let badge: Int
    var onReselect: (AppTab) -> Void

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let icon: String
        var id: AppTab { tab }
    }

    private let items = [
        Item(tab: .catalog, title: "Katalog", icon: "square.grid.2x2"),
        Item(tab: .home, title: "Slevy", icon: "tag"),
        Item(tab: .watch, title: "Seznam", icon: "checklist"),
        Item(tab: .search, title: "Hledat", icon: "magnifyingglass"),
        Item(tab: .more, title: "Více", icon: "line.3.horizontal"),
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                let on = selection == item.tab
                Button {
                    if on { onReselect(item.tab) } else { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                            .overlay(alignment: .topTrailing) {
                                if item.tab == .watch, badge > 0 {
                                    Text("\(badge)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color.ponkRed, in: Capsule())
                                        .offset(x: 10, y: -6)
                                }
                            }
                        Text(item.title)
                            .font(.ponk(11, .semibold, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 56, height: 52)
                    .foregroundStyle(on ? Color.ponkRed : Color.ponkInk)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 16).fill(Color.ponkRed.opacity(0.14)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.tab == .watch && badge > 0 ? "\(item.title), \(badge) zlevněných" : item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(5)
        .ponkGlassPanel(cornerRadius: 24)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// První spuštění: stažení dat, která každé ráno připravuje GitHub.
struct DataSetupView: View {
    var onDone: () -> Void
    @State private var store = DataStore.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader().padding(.horizontal, -14)
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
