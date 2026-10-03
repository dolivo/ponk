import SwiftUI
import UIKit

/// Požadavek na zobrazení mapy prodejny s vyznačeným regálem.
struct MapRequest: Identifiable, Hashable {
    let store: String
    let storeName: String
    let shelf: String
    let field: String?
    var id: String { store + "/" + shelf }
}

/// Plánek prodejny Bauhausu se zvýrazněným místem, kde produkt leží.
/// Plánky a čísla regálů na nich připravuje denní úloha na GitHubu (ponk/storemaps.json).
struct StoreMapSheet: View {
    let request: MapRequest
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var map: StoreMap?
    @State private var image: UIImage?
    @State private var error: String?

    private var shelfNumber: Int? { Int(request.shelf.prefix { $0.isNumber }) }

    private var matches: [StoreMapLabel] {
        guard let n = shelfNumber, let map else { return [] }
        return map.labels.filter { $0.lo <= n && n <= $0.hi }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Regál \(request.shelf)").font(.ponk(20, .heavy, relativeTo: .title3))
                    if let f = request.field, !f.isEmpty, f != "0" {
                        Text("pole \(f)").font(.ponk(20, relativeTo: .title3)).foregroundStyle(Color.ponkMuted)
                    }
                }
                .padding(.horizontal, 16)
                if let map, let image {
                    MapCanvas(map: map, image: image, highlights: matches)
                        .background(Color.white)
                    Text(note(map))
                        .font(.ponk(14, relativeTo: .footnote))
                        .foregroundStyle(Color.ponkMuted)
                        .padding(.horizontal, 16)
                } else if let error {
                    ContentUnavailableView("Mapu nejde zobrazit", systemImage: "map", description: Text(error))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 8)
            .navigationTitle(request.storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func note(_ map: StoreMap) -> String {
        if map.labels.isEmpty {
            return "Pro tuto prodejnu zatím nemám čísla regálů, ukazuji jen plánek. Regál \(request.shelf) najdeš podle čísel v červených rámečcích."
        }
        if matches.isEmpty {
            return "Regál \(request.shelf) na plánku Bauhausu není vyznačený. Zkus se zeptat na informacích."
        }
        return "Zvýrazněná je sekce s regálem \(request.shelf). Dvojitým klepnutím přiblížíš, sevřením prstů zvětšíš."
    }

    private func load() async {
        do {
            let m = try await app.api.get("storemap/\(request.store)", as: StoreMap.self)
            map = m
            guard let url = URL(string: m.image), let img = await ImageCache.shared.load(url) else {
                error = "Plánek se nepodařilo stáhnout. Jsi online?"
                return
            }
            image = img
        } catch {
            self.error = "Pro tuto prodejnu zatím plánek nemám. Stáhni nová data ve Více."
        }
    }
}

/// Plánek s přiblížením a pulzujícím zvýrazněním.
private struct MapCanvas: View {
    let map: StoreMap
    let image: UIImage
    let highlights: [StoreMapLabel]
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / map.width, geo.size.height / map.height)
            let w = map.width * fit, h = map.height * fit
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: w, height: h)
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, l in
                    if let z = l.zone {
                        Rectangle()
                            .fill(Color.ponkRed.opacity(0.22))
                            .overlay(Rectangle().stroke(Color.ponkRed, lineWidth: 2))
                            .frame(width: z.width * fit, height: z.height * fit)
                            .position(x: z.midX * fit, y: z.midY * fit)
                    }
                    Circle()
                        .stroke(Color.ponkRed, lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .scaleEffect(pulse ? 1.6 : 0.9)
                        .opacity(pulse ? 0.15 : 1)
                        .position(x: l.box.midX * fit, y: l.box.midY * fit)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.ponkRed, lineWidth: 3)
                        .frame(width: l.box.width * fit + 8, height: l.box.height * fit + 8)
                        .position(x: l.box.midX * fit, y: l.box.midY * fit)
                }
            }
            .frame(width: w, height: h)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(6, max(1, baseScale * v.magnification)) }
                    .onEnded { _ in baseScale = scale }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.35)) {
                    if scale > 1.05 { setZoom(1, fit: fit, size: CGSize(width: w, height: h)) }
                    else { setZoom(2.5, fit: fit, size: CGSize(width: w, height: h)) }
                }
            }
            .onAppear {
                // rovnou přiblížit na zvýrazněné místo
                if !highlights.isEmpty { setZoom(2.2, fit: fit, size: CGSize(width: w, height: h)) }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }

    /// Přiblíží tak, aby zvýrazněné místo bylo uprostřed.
    private func setZoom(_ s: CGFloat, fit: CGFloat, size: CGSize) {
        scale = s
        baseScale = s
        guard s > 1, let l = highlights.first else {
            offset = .zero
            baseOffset = .zero
            return
        }
        let target = l.zone ?? l.box
        let c = CGPoint(x: target.midX * fit, y: target.midY * fit)
        offset = CGSize(width: -(c.x - size.width / 2) * s, height: -(c.y - size.height / 2) * s)
        baseOffset = offset
    }
}
