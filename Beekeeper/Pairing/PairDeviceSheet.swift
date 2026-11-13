import CoreImage.CIFilterBuiltins
import HiveKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens a pairing window on the Hive and shows its code, as a QR code and as text to copy, until a
/// device pairs or the window expires. Closing the sheet closes the window.
struct PairDeviceSheet: View {
    let hive: KnownHive
    let link: HiveLink
    let onPaired: () -> Void

    private enum Phase: Equatable {
        case opening
        case open(PairingWindow, expiresAt: Date)
        case paired(deviceName: String)
        case expired
        case failed(String)
    }

    /// Often enough that the sheet says a device paired as soon as the person looks back at it.
    private static let checkInterval = Duration.seconds(2)

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.opening
    @State private var isCopied = false

    var body: some View {
        SheetLayout(
            title: title,
            cancel: isFinished ? nil : SheetButton(title: "Cancel") { close() },
            confirm: isFinished ? SheetButton(title: "Done") { close() } : nil,
            secondary: phase == .expired ? SheetButton(title: "New Code") { Task { await open() } } : nil
        ) {
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                Text(title)
                    .font(.title2.bold())
                #endif
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macSheetSize(width: 520, height: 560)
        .interactiveDismissDisabled()
        .task { await open() }
        .task(id: openWindowID) { await watch() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .open(let window, let expiresAt):
            openWindow(window, expiresAt: expiresAt)
        case .opening, .paired, .expired, .failed:
            // Fills what the open window's code would, so it sits in the middle of the sheet.
            outcome
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var outcome: some View {
        switch phase {
        case .opening:
            ProgressView("Opening a pairing window…")
        case .paired(let deviceName):
            ContentUnavailableView(
                "“\(deviceName)” Paired",
                systemImage: "checkmark.circle",
                description: Text("It can now manage “\(hive.name)”. It shows in Devices, where it can be revoked.")
            )
        case .expired:
            ContentUnavailableView(
                "The Code Expired",
                systemImage: "clock.badge.xmark",
                description: Text("Nobody paired with it. Make a new code to try again.")
            )
        case .failed(let message):
            ContentUnavailableView("Couldn't Open a Pairing Window", systemImage: "exclamationmark.triangle", description: Text(message))
        case .open:
            EmptyView()
        }
    }

    private func openWindow(_ window: PairingWindow, expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("In Beekeeper on the new device, choose File › Add Hive and paste this code.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PairingQRCode(text: window.code)
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity)

            Text(window.code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            HStack {
                Button(isCopied ? "Copied" : "Copy Code", systemImage: isCopied ? "checkmark" : "doc.on.doc") {
                    Self.copy(window.code)
                    isCopied = true
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Expires in \(Self.remaining(until: expiresAt, now: context.date))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Label(
                "Anyone with this code can pair a device with full access until it's used or expires.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        "Pair a Device with “\(hive.name)”"
    }

    private var isFinished: Bool {
        if case .paired = phase { return true }
        return false
    }

    private var openWindowID: UUID? {
        if case .open(let window, _) = phase { return window.id }
        return nil
    }

    private func open() async {
        phase = .opening
        isCopied = false
        do {
            let reason = "let a new device pair with “\(hive.name)”, giving it full access"
            let window: PairingWindow = try await link.confirmed("POST", HiveEndpoint.pairingWindow, reason: reason)
            phase = .open(window, expiresAt: .now.addingTimeInterval(TimeInterval(window.expiresInSeconds)))
        } catch ConfirmationKeyError.cancelled {
            dismiss()
        } catch {
            phase = .failed(Self.message(for: error, hiveName: hive.name))
        }
    }

    /// Until the window is used or expires, or the sheet closes.
    private func watch() async {
        guard case .open(let window, let expiresAt) = phase else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.checkInterval)
            guard !Task.isCancelled else { return }
            let state: PairingWindowState? = try? await link.perform { try await $0.get(HiveEndpoint.pairingWindow) }
            switch state {
            case .used(window.id, _, let deviceName):
                phase = .paired(deviceName: deviceName)
                onPaired()
                return
            case .open(window.id, _):
                continue
            case .closed, .open, .used:
                phase = .expired
                return
            case nil:
                if Date.now >= expiresAt {
                    phase = .expired
                    return
                }
            }
        }
    }

    private func close() {
        if case .open = phase {
            Task { try? await link.perform { try await $0.delete(HiveEndpoint.pairingWindow) } }
        }
        dismiss()
    }

    private static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Not marked as concealed or local only, as a recovery key is: Universal Clipboard taking it to the
    /// new device is the point, and it's single-use and expires within minutes.
    private static func copy(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
    }

    private static func message(for error: any Error, hiveName: String) -> String {
        if let refused = error as? HiveRequestError, refused.status == 422,
           (try? JSONDecoder().decode(PairingWindowRefusal.self, from: refused.body))?.problem == .noAddressOptions {
            return "Add an address other devices can reach “\(hiveName)” at, under Addresses for Other Devices in Settings."
        }
        if let refused = error as? HiveRequestError, refused.status == 503 {
            return "The Hive is restarting. Try again in a moment."
        }
        return HiveLink.message(for: error)
    }
}

/// Drawn dark on light whatever the appearance, since that's what cameras read.
private struct PairingQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .padding(12)
                // A QR code needs a light quiet zone around it to scan, in dark mode too.
                .background(Color.white, in: .rect(cornerRadius: 8))
                .accessibilityLabel(Text("Pairing code as a QR code"))
        }
    }

    private static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
