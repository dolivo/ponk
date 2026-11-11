import ActivityKit
import Foundation

extension Notification.Name {
    /// Nákupní seznam se změnil mimo obrazovku seznamu (např. tlačítkem na zamčené obrazovce).
    static let ponkListChanged = Notification.Name("ponkListChanged")
}

/// Spouští, aktualizuje a ukončuje živou aktivitu „Nakupuji“.
@MainActor
final class ShoppingActivityController {
    static let shared = ShoppingActivityController()

    private var activity: Activity<ShoppingActivityAttributes>? {
        Activity<ShoppingActivityAttributes>.activities.first
    }

    var isRunning: Bool { activity != nil }
    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(listName: String, storeName: String, stops: [ShoppingActivityAttributes.Stop], total: Int) {
        let state = ShoppingActivityAttributes.ContentState(stops: Array(stops.prefix(4)), remaining: stops.count, total: total)
        if let a = activity {
            Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        let attrs = ShoppingActivityAttributes(listName: listName, storeName: storeName)
        _ = try? Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil))
    }

    func update(stops: [ShoppingActivityAttributes.Stop], total: Int) {
        guard let a = activity else { return }
        if stops.isEmpty { end(); return }
        let state = ShoppingActivityAttributes.ContentState(stops: Array(stops.prefix(4)), remaining: stops.count, total: total)
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        for a in Activity<ShoppingActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Odškrtnutí z tlačítka „Mám“: zapíše do seznamu a posune aktivitu na další regál.
    func checkOff(itemID: Int) async {
        let store = DataStore.shared
        if !(await store.engine.hasData) { await store.start() }
        let body = try? JSONSerialization.data(withJSONObject: ["checked": true])
        _ = try? await store.engine.handleJSON(method: "POST", path: "listitem/\(itemID)", query: [:], body: body)
        if let a = activity {
            var state = a.content.state
            state.stops.removeAll { $0.id == itemID }
            state.remaining = max(0, state.remaining - 1)
            if state.remaining == 0 {
                await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
            } else {
                await a.update(ActivityContent(state: state, staleDate: nil))
            }
        }
        NotificationCenter.default.post(name: .ponkListChanged, object: nil)
    }
}
