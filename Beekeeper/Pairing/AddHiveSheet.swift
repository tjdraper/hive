import HiveKit
import SwiftUI

/// Opens the Add Hive sheet, from the File menu, the empty list, or a Hive this device has to pair with again.
struct AddHiveAction {
    let open: () -> Void

    func callAsFunction() {
        open()
    }
}

extension EnvironmentValues {
    @Entry var addHive: AddHiveAction?
}

extension FocusedValues {
    @Entry var addHive: AddHiveAction?
}

/// Pairs this device with a Hive by pasting a pairing code from a device already paired with it, or on
/// iPhone and iPad by scanning its QR code.
struct AddHiveSheet: View {
    let onAdded: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(HiveListStore.self) private var store
    @State private var codeText = ""
    @State private var deviceName = ThisDevice.name
    @State private var isPairing = false
    @State private var isScanning = false
    @State private var failure: String?

    var body: some View {
        SheetLayout(
            title: "Add a Hive",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(title: "Pair", isDisabled: !canPair) { Task { await pair() } },
            message: isPairing ? .working(nil) : nil
        ) {
            form
        }
        .macSheetSize(width: 520, height: 420)
        #if os(iOS)
        .sheet(isPresented: $isScanning) {
            PairingCodeScanner { code in
                codeText = code.text
                Task { await pair() }
            }
        }
        #endif
        // The code's Hive may be found on the local network, at an address the code doesn't carry.
        .task { store.discoverLocalHives() }
    }

    private var form: some View {
        Form {
            Section {
                #if os(iOS)
                if PairingCodeScanner.isSupported {
                    Button("Scan the QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
                        .disabled(isPairing)
                }
                #endif
                StackedRow(title: "Pairing Code") {
                    TextField("Pairing Code", text: $codeText, prompt: Text("hive1:…"), axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3 ... 6)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .stackedField("Pairing Code")
                }
            } footer: {
                Text(Self.codeFooter)
                    .foregroundStyle(.secondary)
            }

            Section {
                StackedRow(title: "This Device's Name") {
                    TextField("This Device's Name", text: $deviceName)
                        .stackedField("This Device's Name")
                }
            } footer: {
                Text("The Hive lists this device by this name.")
                    .foregroundStyle(.secondary)
            }

            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private static var codeFooter: String {
        #if os(macOS)
        "On a device already paired with the Hive, open its Devices page and choose Pair a Device, then copy the code it shows."
        #else
        "On a device already paired with the Hive, open its Devices page and choose Pair a Device, then scan the QR code it "
            + "shows, or paste the code."
        #endif
    }

    private var canPair: Bool {
        !isPairing && !codeText.isEmpty && !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func pair() async {
        guard canPair else { return }
        failure = nil
        guard let code = PairingCode(text: codeText) else {
            failure = "That isn't a whole pairing code. Copy it again from the other device."
            return
        }
        if let known = store.hive(code.hiveID), store.link(for: known.id)?.status == .connected {
            failure = "This device is already paired with “\(known.name)”."
            return
        }

        isPairing = true
        defer { isPairing = false }
        do {
            let hiveID = try await store.pairWithCode(code, deviceName: deviceName.trimmingCharacters(in: .whitespaces))
            onAdded(hiveID)
            dismiss()
        } catch {
            failure = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case HiveConnectionError.pairingRefused:
            "The Hive turned the code down: it was used, expired, or another code was made since. Make a new one."
        case HiveConnectionError.wrongKey, CodePairingError.otherHive:
            "The Hive at the code's addresses isn't the one the code is for, so Beekeeper didn't pair with it."
        case HiveConnectionError.lockedOut:
            "Too many tries from this network. Try again in 15 minutes."
        case HiveConnectionError.unexpectedStatus(422):
            "The Hive turned down this device's name. Use a shorter one."
        case is URLError:
            "Couldn't reach the Hive at any address in the code. Check this device can reach it, such as over Tailscale."
        case DeviceKeyError.secureEnclaveUnavailable:
            "This device has no Secure Enclave for Beekeeper's key."
        default:
            HiveLink.message(for: error)
        }
    }
}
