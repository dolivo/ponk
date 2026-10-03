import SwiftUI
import UIKit
import VisionKit

/// Čtečka čárových kódů: v prodejně namíříš na EAN a Ponk najde produkt s historií ceny.
struct ScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScanner { code in
                        onCode(code)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("Namiř na čárový kód na zboží nebo cenovce")
                            .font(.ponk(16, .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .ponkGlassCapsule(tint: Color.black.opacity(0.2))
                            .padding(.bottom, 30)
                    }
                } else {
                    ContentUnavailableView("Čtečka není dostupná", systemImage: "barcode.viewfinder",
                                           description: Text("Povol Ponku přístup ke kameře v Nastavení, nebo tento iPhone čtení kódů nepodporuje."))
                }
            }
            .navigationTitle("Načíst kód")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } }
            }
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue, !value.isEmpty {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(value)
                    return
                }
            }
        }
    }
}
