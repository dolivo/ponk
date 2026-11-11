import SwiftUI
import UIKit

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

private struct SideMenuSideKey: EnvironmentKey { static let defaultValue = MenuSide.bottom }

extension EnvironmentValues {
    /// Na které straně je boční menu (u spodní lišty `.bottom`).
    var sideMenuSide: MenuSide {
        get { self[SideMenuSideKey.self] }
        set { self[SideMenuSideKey.self] = newValue }
    }
}

/// Seznamy s ovládáním u okraje (cena, mazání přejetím) se zúží, aby nebyly pod bočním menem.
private struct ClearOfSideMenu: ViewModifier {
    @Environment(\.sideMenuSide) private var side

    func body(content: Content) -> some View {
        switch side {
        case .right: content.safeAreaPadding(.trailing, 62)
        case .left: content.safeAreaPadding(.leading, 62)
        case .bottom: content
        }
    }
}

extension View {
    func clearOfSideMenu() -> some View { modifier(ClearOfSideMenu()) }
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
    /// Druhé klepnutí na Hledat otevře pole hledání s klávesnicí.
    @State private var searchFocus = 0
    /// Je vysunutá klávesnice? Boční menu se pak přesune nahoru, aby nebylo schované pod ní.
    @State private var keyboardUp = false
    /// Přechod mezi záložkami: odkud se odchází a kterým směrem (dolů v menu = +1, nahoru = −1).
    @State private var fromTab: AppTab?
    @State private var direction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            SearchTab(focusTrigger: searchFocus)
        case .more:
            NavigationStack { MoreView() }
        }
    }

    /// Klasická spodní lišta (systémová, na iOS 26 Liquid Glass).
    private var tabBarLayout: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == tab { reselect(new) } else { tab = new }
        })) {
            Tab("Katalog", systemImage: "square.grid.2x2", value: AppTab.catalog) { screen(.catalog).modifier(TabEntrance()) }
            Tab("Slevy", systemImage: "tag", value: AppTab.home) { screen(.home).modifier(TabEntrance()) }
            Tab("Seznam", systemImage: "checklist", value: AppTab.watch) { screen(.watch).modifier(TabEntrance()) }
                .badge(app.meta?.watched_drops ?? 0)
            Tab("Více", systemImage: "line.3.horizontal", value: AppTab.more) { screen(.more).modifier(TabEntrance()) }
            // V iOS 26 se hledání zobrazí jako samostatné skleněné tlačítko vedle lišty.
            Tab(value: AppTab.search, role: .search) { screen(.search).modifier(TabEntrance()) }
        }
        .ponkMinimizingTabBar()
    }

    /// Přepnutí záložky v bočním menu: nejdřív se nová obrazovka bez animace postaví na stranu,
    /// odkud přijede, a v dalším kroku se animovaně prohodí se starou.
    private func switchTab(to new: AppTab) {
        guard new != tab else { return }
        let all = AppTab.allCases
        direction = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: tab) ?? 0) ? 1 : -1
        fromTab = tab
        Task { @MainActor in tab = new }
    }

    /// Klepnutí na už otevřenou záložku: Hledat otevře klávesnici, ostatní se vrátí na začátek.
    private func reselect(_ t: AppTab) {
        if t == .search { searchFocus += 1 } else if side != .bottom { resets[t, default: 0] += 1 }
    }

    /// Svislé menu u okraje obrazovky. Záložky se vytvoří při prvním otevření a pak zůstávají
    /// naživu (skryté), takže si drží rozscrollovaný seznam i otevřené detaily jako u spodní lišty.
    private var sideLayout: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                if visited.contains(t) || t == tab {
                    let active = t == tab
                    let leaving = t == fromTab && !active
                    screen(t)
                        .environment(\.sideMenuSide, side)
                        .id(resets[t, default: 0])
                        // Přechod ve směru menu: nová obrazovka vyplave zespodu (nebo shora),
                        // stará se zmenší a rozmaže do pozadí, vše na pružině.
                        .scaleEffect(active || reduceMotion ? 1 : (leaving ? 0.93 : 1.03))
                        .offset(y: active || reduceMotion ? 0 : (leaving ? -direction * 36 : direction * 70))
                        .blur(radius: active || reduceMotion ? 0 : 10)
                        .opacity(active ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.84), value: tab)
                        .zIndex(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(t != tab)
                }
            }
        }
        .overlay {
            SideMenu(selection: Binding(get: { tab }, set: { switchTab(to: $0) }),
                     badge: app.meta?.watched_drops ?? 0, side: side) { t in
                reselect(t)
            }
            .padding(side == .left ? .leading : .trailing, 8)
            // dole nad plovoucími tlačítky Filtry / Řazení v dosahu palce;
            // s klávesnicí nahoře pod horní lištou, aby šlo dál klepat
            .padding(.bottom, keyboardUp ? 0 : 92)
            .padding(.top, keyboardUp ? 50 : 0) // pod lištou s tlačítky (ty zůstanou klikatelné)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: keyboardUp ? (side == .left ? .topLeading : .topTrailing)
                                         : (side == .left ? .bottomLeading : .bottomTrailing))
            // přepnutí strany ve Více: menu plynule přejede na druhý okraj
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: side)
            // s klávesnicí pružně vyjede nahoru a po jejím schování se vrátí
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: keyboardUp)
            .ignoresSafeArea(.keyboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            // jen opravdová klávesnice, ne lišta zkratek u hardwarové klávesnice
            let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            if (frame?.height ?? 300) > 120 { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .onChange(of: tab, initial: true) { _, t in visited.insert(t) }
    }
}

/// Spodní lišta: obsah záložky při přepnutí pružně vyjede a zaostří se.
private struct TabEntrance: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.85)) { shown = true }
            }
            .onDisappear { shown = false }
    }
}

/// Svislé skleněné menu pro ovládání jednou rukou.
/// Animace jako u systémové lišty iOS: zvýraznění vybrané záložky pružně přejede na novou,
/// ikona se při klepnutí zhoupne a vyplní, tlačítko se při stisku zmáčkne, odznak se přepočítá
/// a menu při spuštění vyjede od okraje.
struct SideMenu: View {
    @Binding var selection: AppTab
    let badge: Int
    var side: MenuSide = .right
    var onReselect: (AppTab) -> Void

    @Namespace private var ns
    /// Záložka, pod kterou je zvýraznění (animuje se odděleně od přepnutí obrazovky).
    @State private var shown: AppTab?
    @State private var bounce: [AppTab: Int] = [:]
    @State private var appeared = false

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
                let on = (shown ?? selection) == item.tab
                Button {
                    bounce[item.tab, default: 0] += 1
                    if selection == item.tab { onReselect(item.tab) } else { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .symbolVariant(on ? .fill : .none)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce.down, value: bounce[item.tab, default: 0])
                            .frame(height: 22)
                            .overlay(alignment: .topTrailing) {
                                if item.tab == .watch, badge > 0 {
                                    Text("\(badge)")
                                        .font(.system(size: 10, weight: .bold))
                                        .contentTransition(.numericText(value: Double(badge)))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color.ponkRed, in: Capsule())
                                        .offset(x: 10, y: -6)
                                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: badge)
                        Text(item.title)
                            .font(.ponk(11, .semibold, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 56, height: 52)
                    .foregroundStyle(on ? Color.ponkRed : Color.ponkInk)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.ponkRed.opacity(0.14))
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel(item.tab == .watch && badge > 0 ? "\(item.title), \(badge) zlevněných" : item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(5)
        .ponkGlassPanel(cornerRadius: 24)
        .sensoryFeedback(.selection, trigger: selection)
        .offset(x: appeared ? 0 : (side == .left ? -90 : 90))
        .opacity(appeared ? 1 : 0)
        .onChange(of: selection, initial: true) { _, t in
            if shown == nil { shown = t; return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { shown = t }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.25)) { appeared = true }
        }
    }
}

/// Stisk tlačítka v menu: lehké zmáčknutí s pružným návratem (jako systémové ovládací prvky).
private struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
