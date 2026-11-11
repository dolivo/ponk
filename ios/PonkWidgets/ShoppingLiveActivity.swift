import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// „Nakupuji“: další regál po cestě prodejnou na zamčené obrazovce a v Dynamic Islandu.
struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            LockScreenShopping(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let next = context.state.stops.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.remaining)", systemImage: "cart.fill")
                        .font(.headline).foregroundStyle(WColor.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let n = next {
                        Button(intent: CheckShoppingItemIntent(itemID: n.id)) {
                            Label("Mám", systemImage: "checkmark")
                        }
                        .tint(WColor.green)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(next?.place ?? "Nakupuji").font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let n = next {
                        Text("\(n.qty) · \(n.title)").font(.subheadline).lineLimit(2)
                    } else {
                        Text("Další položky najdeš v Ponku").font(.subheadline)
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill").foregroundStyle(WColor.red)
            } compactTrailing: {
                Text(next?.shelf.map { "R\($0)" } ?? "\(context.state.remaining)")
                    .font(.caption.weight(.heavy)).monospacedDigit()
            } minimal: {
                Text("\(context.state.remaining)").font(.caption.weight(.heavy)).foregroundStyle(WColor.red)
            }
            .widgetURL(URL(string: "ponk://list"))
        }
    }
}

private struct LockScreenShopping: View {
    let context: ActivityViewContext<ShoppingActivityAttributes>

    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.storeName, systemImage: "cart.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("zbývá \(s.remaining) z \(s.total)").font(.caption.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.85))
            if let n = s.stops.first {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.place ?? "Bez regálu").font(.title3.weight(.heavy)).foregroundStyle(.white)
                        Text("\(n.qty) · \(n.title)").font(.subheadline).foregroundStyle(.white).lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Button(intent: CheckShoppingItemIntent(itemID: n.id)) {
                        Label("Mám", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                    }
                    .tint(WColor.green)
                }
                if s.stops.count > 1 {
                    Text("Pak: " + s.stops.dropFirst().prefix(2).map { ($0.place.map { "\($0) – " } ?? "") + $0.title }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            } else {
                Text(s.remaining > 0 ? "Další položky najdeš v Ponku" : "Hotovo, všechno v košíku")
                    .font(.headline).foregroundStyle(.white)
            }
            ProgressView(value: Double(max(0, s.total - s.remaining)), total: Double(max(1, s.total)))
                .tint(WColor.green)
        }
        .padding(14)
    }
}
