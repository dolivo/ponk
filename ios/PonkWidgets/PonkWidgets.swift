import SwiftUI
import WidgetKit

@main
struct PonkWidgets: WidgetBundle {
    var body: some Widget {
        DealsWidget()
        ShoppingLiveActivity()
    }
}

enum WColor {
    static let red = Color(red: 0.8, green: 0, blue: 0)
    static let green = Color(red: 0, green: 0.53, blue: 0.25)
    static let yellow = Color(red: 0.95, green: 0.76, blue: 0)
}

func wMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "cs_CZ")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return (f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))") + " Kč"
}
