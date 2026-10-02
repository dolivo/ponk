import SwiftUI
import UIKit

/// Mezipaměť obrázků produktů. Obrázky se stahují v plném rozlišení (kvalita zůstává),
/// jen se dekódují mimo hlavní vlákno a drží v paměti, takže se při posouvání
/// regálu znovu nestahují ani nedekódují.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()

    /// Větší diskovou mezipaměť sdílí všechna síťová spojení (obrázky přežijí i restart aplikace).
    static func configureURLCache() {
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    func image(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> UIImage? {
        if let hit = image(for: url) { return hit }
        guard let result = try? await URLSession.shared.data(from: url),
              ((result.1 as? HTTPURLResponse)?.statusCode ?? 200) == 200,
              let decoded = UIImage(data: result.0) else { return nil }
        let ready = await decoded.byPreparingForDisplay() ?? decoded
        let cost = Int(ready.size.width * ready.scale * ready.size.height * ready.scale * 4)
        memory.setObject(ready, forKey: url as NSURL, cost: cost)
        return ready
    }

    func removeAll() {
        memory.removeAllObjects()
    }
}

/// Náhrada za AsyncImage: bez probliknutí při návratu do regálu, s mezipamětí.
/// `fallback` se ukáže hned (např. menší, už stažený obrázek) a použije se, když hlavní selže.
struct CachedImage: View {
    let url: URL?
    var fallback: URL? = nil
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, fallback: URL? = nil) {
        self.url = url
        self.fallback = fallback
        let cache = ImageCache.shared
        _image = State(initialValue: url.flatMap(cache.image(for:)) ?? fallback.flatMap(cache.image(for:)))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").font(.title2).foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await load() }
    }

    private func load() async {
        let cache = ImageCache.shared
        guard let url else { failed = true; return }
        if let hit = cache.image(for: url) { image = hit; return }
        var loaded = await cache.load(url)
        if loaded == nil, let fallback, !Task.isCancelled { loaded = await cache.load(fallback) }
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        } else if image == nil {
            failed = true
        }
    }
}

/// Fotka na celou obrazovku: přiblížení dvěma prsty nebo dvojitým klepnutím, posun prstem.
struct ZoomableImage: View {
    let url: URL?
    var fallback: URL? = nil
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        CachedImage(url: url, fallback: fallback)
            .scaleEffect(scale)
            .offset(offset)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 }
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(6, max(1, baseScale * v.magnification)) }
                    .onEnded { _ in
                        baseScale = scale
                        if scale <= 1.01 { withAnimation(.spring(duration: 0.3)) { reset() } }
                    }
            )
            // posun jen při přiblížení, jinak se stránkuje mezi fotkami
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .accessibilityAddTraits(.isImage)
    }

    private func reset() {
        scale = 1; baseScale = 1
        offset = .zero; baseOffset = .zero
    }
}

struct ZoomGallery: View {
    let pictures: [String]
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(pictures.enumerated()), id: \.offset) { i, path in
                // větší rozlišení pro přiblížení; menší verze z detailu se ukáže hned
                ZoomableImage(url: productImageURL(path, w: 1200, h: 1488),
                              fallback: productImageURL(path, w: 600, h: 744))
                    .padding(12)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: pictures.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color.white.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).padding(4)
            }
            .ponkGlassButton()
            .buttonBorderShape(.circle)
            .padding(16)
            .accessibilityLabel("Zavřít")
        }
    }
}
