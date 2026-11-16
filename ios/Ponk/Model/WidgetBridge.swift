import Foundation
import WidgetKit

/// Posílá widgetu „Můj Bauhaus“ čerstvá data: po změně hlídaných nebo seznamu, po stažení
/// nových dat a při odchodu z aplikace. Víc změn těsně po sobě se sloučí do jednoho zápisu.
@MainActor
enum WidgetBridge {
    static let kind = "PonkMine"
    private static var pending: Task<Void, Never>?

    /// Obnoví data widgetu za chvíli (vhodné po každé drobné změně).
    static func refresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await refreshNow()
        }
    }

    /// Obnoví data widgetu hned.
    static func refreshNow() async {
        let store = DataStore.shared
        guard await store.engine.hasData else { return }
        let list = UserDefaults.standard.integer(forKey: "currentList")
        guard var snapshot = try? await store.engine.handleDecoded(WidgetSnapshot.self, path: "widget",
                                                                    query: ["list": "\(list)"]) else { return }
        snapshot.updated = Date()
        if WidgetShare.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
