#if os(iOS)
import AVFoundation
import HiveKit
import SwiftUI
import Vision
import VisionKit

/// Scans the QR code a paired device shows in Pair a Device, and hands back the first whole pairing
/// code it sees. Any other QR code is ignored.
struct PairingCodeScanner: View {
    let onScan: (PairingCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    /// False on devices whose camera can't scan, such as those from before the A12 chip.
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan the Pairing Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
        .task {
            if access == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                access = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch access {
        case .authorized:
            QRCodeScannerView { code in
                onScan(code)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                Text("Point the camera at the QR code in Pair a Device on a device already paired with the Hive.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .padding()
            }
        case .notDetermined:
            ProgressView()
        default:
            ContentUnavailableView {
                Label("Camera Access Is Off", systemImage: "camera")
            } description: {
                Text("Allow Beekeeper to use the camera in Settings to scan the code, or paste the code instead.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (PairingCode) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    /// Scanning can only start once the scanner is on screen, which it isn't yet when it's made.
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        guard !scanner.isScanning else { return }
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (PairingCode) -> Void
        private var hasScanned = false

        init(onScan: @escaping (PairingCode) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue,
                      let code = PairingCode(text: text)
                else { continue }
                hasScanned = true
                dataScanner.stopScanning()
                onScan(code)
                return
            }
        }
    }
}
#endif
