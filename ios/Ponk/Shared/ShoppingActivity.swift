import ActivityKit
import AppIntents
import Foundation

/// Živá aktivita „Nakupuji“ na zamčené obrazovce a v Dynamic Islandu: další regál po cestě
/// prodejnou a kolik položek zbývá. Soubor je v aplikaci i v rozšíření s widgety.
struct ShoppingActivityAttributes: ActivityAttributes {
    struct Stop: Codable, Hashable {
        var id: Int
        var title: String
        var shelf: String?
        var field: String?
        var qty: String

        var place: String? {
            guard let shelf, !shelf.isEmpty else { return nil }
            return "Regál \(shelf)" + ((field ?? "").isEmpty || field == "0" ? "" : ", pole \(field!)")
        }
    }

    struct ContentState: Codable, Hashable {
        var stops: [Stop]
        var remaining: Int
        var total: Int
    }

    var listName: String
    var storeName: String
}

/// Tlačítko „Mám“ na zamčené obrazovce: odškrtne položku v nákupním seznamu.
/// Běží v aplikaci (na pozadí), takže zapíše do stejné databáze jako ruční odškrtnutí.
struct CheckShoppingItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Odškrtnout položku"
    static var isDiscoverable = false

    @Parameter(title: "Položka") var itemID: Int

    init() {}
    init(itemID: Int) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ShoppingActivityController.shared.checkOff(itemID: itemID)
        #endif
        return .result()
    }
}
