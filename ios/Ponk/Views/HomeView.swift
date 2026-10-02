import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var home: HomeResponse?
    @State private var error: String?

    private var quick: [ResultsRoute] {
        let store = app.myStore ?? "888"
        return [
            ResultsRoute(query: ["label": "sell_off", "store": store, "sort": "discount"], title: "Výprodej skladem"),
            ResultsRoute(query: ["drop_days": "7", "sort": "drop"], title: "Zlevněno za 7 dní"),
            ResultsRoute(query: ["disc": "50", "sort": "discount"], title: "Sleva 50 % a víc"),
            ResultsRoute(query: ["label": "free_shipping"], title: "Doprava zdarma"),
            ResultsRoute(query: ["unit": "1", "sort": "unit"], title: "Cena za jednotku"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OfflineNotice()
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(quick, id: \.title) { route in
                                NavigationLink(value: route) {
                                    Text(route.title).font(.ponk(15, .semibold, relativeTo: .subheadline))
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }

                if let meta = app.meta, meta.products == 0 {
                    SyncCard()
                        .padding(.horizontal, 14)
                }

                if let home {
                    ForEach(home.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeader(title: section.title) {
                                NavigationLink("Zobrazit vše", value: ResultsRoute(query: section.query.values, title: section.title))
                                    .font(.ponk(16, .semibold))
                                    .foregroundStyle(Color.ponkRedDeep)
                            }
                            Rail(items: section.items)
                        }
                    }
                    if home.sections.isEmpty, (app.meta?.products ?? 0) > 0 {
                        ContentUnavailableView("Zatím žádné změny cen", systemImage: "tag",
                                               description: Text("Po druhé denní kontrole se tu objeví zlevněné zboží."))
                    }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }

                if let meta = app.meta, meta.products > 0 {
                    Text("V katalogu je \(money(Double(meta.products))) produktů. Poslední kontrola cen \(shortDayTime(meta.last_run?.finished)).")
                        .font(.ponk(14, relativeTo: .footnote))
                        .foregroundStyle(Color.ponkMuted)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 4)
        }
        .ponkPage()
        .navigationTitle("Ponk")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            home = try await app.api.get("home", as: HomeResponse.self)
            error = nil
            await app.loadMeta()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Stav denní kontroly cen s průběhem; pokud běží, sám se obnovuje.
struct SyncCard: View {
    @Environment(AppModel.self) private var app
    @State private var status: SyncStatus?

    var body: some View {
        let st = status ?? app.meta?.sync
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(st?.running == true ? (st?.phase ?? "") : "Kontrola cen")
                        .font(.ponk(17, .heavy, relativeTo: .headline))
                    Group {
                        if let st, st.running {
                            Text("\(money(Double(st.done))) z \(money(Double(st.total)))")
                        } else if let msg = st?.message, !msg.isEmpty {
                            Text(msg)
                        } else {
                            Text("Naposledy \(shortDayTime(app.meta?.last_run?.finished))")
                        }
                    }
                    .font(.ponk(14, relativeTo: .footnote))
                    .foregroundStyle(Color.ponkMuted)
                }
                Spacer()
                Button(st?.running == true ? "Probíhá…" : "Zkontrolovat teď") {
                    Task { await start() }
                }
                .buttonStyle(.glass)
                .disabled(st?.running == true)
            }
            if let st, st.running {
                ProgressView(value: st.progress).tint(.ponkRed)
            }
        }
        .padding(14)
        .background(Color.ponkSurface, in: RoundedRectangle(cornerRadius: 6))
        .task(id: st?.running) { await poll() }
    }

    private func start() async {
        try? await app.api.send("POST", "sync")
        status = try? await app.api.get("sync", as: SyncStatus.self)
    }

    private func poll() async {
        while !Task.isCancelled {
            guard let s = try? await app.api.get("sync", as: SyncStatus.self) else { return }
            status = s
            if !s.running { await app.loadMeta(); return }
            try? await Task.sleep(for: .seconds(2.5))
        }
    }
}
