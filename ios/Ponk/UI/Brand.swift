import SwiftUI
import UIKit

/// Logo Bauhaus. Když je v Assets obrázek „BauhausLogo“ (originální logo jako SVG/PDF),
/// použije se ten; jinak se kreslí červený obdélník s bílým nápisem písmem aplikace.
struct BauhausLogo: View {
    var height: CGFloat = 26

    static let red = Color(uiColor: UIColor(hex: 0xCC0000))
    private static let original = UIImage(named: "BauhausLogo")

    var body: some View {
        Group {
            if let original = Self.original {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                Text("BAUHAUS")
                    .font(.custom("BarlowSemiCondensed-ExtraBold", fixedSize: height * 0.64))
                    .tracking(height * 0.04)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, height * 0.34)
                    .frame(height: height)
                    .background(Self.red)
            }
        }
        .accessibilityLabel("Bauhaus")
    }
}

/// Značka v horní liště (jako YouTube Premium): logo Bauhaus + nápis „ponk“.
struct BrandMark: View {
    var height: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: height * 0.3) {
            BauhausLogo(height: height)
            Text("ponk")
                .font(.ponk(height * 1.05, .heavy, relativeTo: .title3))
                .foregroundStyle(Color.ponkInk)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ponk for Bauhaus")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Hlavička „ponk for BAUHAUS“ (uvítání při prvním spuštění, Více).
struct BrandHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("ponk")
                .font(.ponk(34, .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Color.ponkInk)
            Text("for")
                .font(.ponk(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Color.ponkMuted)
            BauhausLogo(height: 28)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ponk for Bauhaus")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Logo vlevo v horní liště místo titulku. Na iOS 26 bez skleněného podkladu.
private struct BrandToolbar: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(iOS 26.0, *) {
            content
                .toolbar(removing: .title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { BrandMark() }
                        .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
                .toolbar(removing: .title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { BrandMark() }
                }
        }
    }
}

extension View {
    /// Titulek obrazovky nahradí logo vlevo v liště (titulek zůstává pro tlačítko Zpět a VoiceOver).
    func ponkBrandToolbar(_ enabled: Bool = true) -> some View {
        modifier(BrandToolbar(enabled: enabled))
    }
}

/// Úvodní animace po spuštění. Navazuje na launch screen (stejná barva pozadí),
/// logo pružně naskočí, pod ním „ponk“, pak se celé jemně rozplyne (~1,5 s).
/// Se zapnutým Omezit pohyb jen krátké prolnutí.
struct SplashView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIn = false
    @State private var textIn = false
    @State private var out = false

    var body: some View {
        ZStack {
            Color.ponkPage.ignoresSafeArea()
            VStack(spacing: 16) {
                BauhausLogo(height: 64)
                    .scaleEffect(logoIn ? 1 : 0.55)
                    .opacity(logoIn ? 1 : 0)
                Text("ponk")
                    .font(.ponk(46, .heavy, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ponkInk)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? 0 : 18)
            }
            .scaleEffect(out ? 1.12 : 1)
        }
        .opacity(out ? 0 : 1)
        .allowsHitTesting(!out)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { logoIn = true; textIn = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.25)) { out = true }
            try? await Task.sleep(for: .milliseconds(250))
            onFinish()
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { logoIn = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { textIn = true }
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { out = true }
        try? await Task.sleep(for: .milliseconds(420))
        onFinish()
    }
}
