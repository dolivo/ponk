import SwiftUI
import UIKit

/// Logo Bauhaus: červený obdélník s bílým nápisem. Kreslí se písmem aplikace,
/// takže je ostré v každé velikosti a nepotřebuje obrázek.
struct BauhausLogo: View {
    var height: CGFloat = 26

    static let red = Color(uiColor: UIColor(hex: 0xCC0000))

    var body: some View {
        Text("BAUHAUS")
            .font(.custom("BarlowSemiCondensed-ExtraBold", fixedSize: height * 0.64))
            .tracking(height * 0.04)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, height * 0.34)
            .frame(height: height)
            .background(Self.red)
            .accessibilityLabel("Bauhaus")
    }
}

/// Hlavička „ponk for BAUHAUS“ na úvodní obrazovce.
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
