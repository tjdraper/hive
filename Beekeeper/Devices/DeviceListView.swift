import HiveKit
import SwiftUI

struct DeviceListView: View {
    let hive: KnownHive
    let link: HiveLink

    @State private var devices: [DeviceSummary] = []
    @State private var failure: String?
    @State private var isConfirmingSelfRevoke = false
    @State private var isPairing = false

    var body: some View {
        Table(devices) {
            TableColumn("Name") { device in
                HStack(spacing: 6) {
                    Text(device.name)
                    if device.id == link.deviceID {
                        Text(Self.thisDeviceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Paired") { device in
                Text(device.pairedAt, format: .dateTime.day().month().year())
            }
            TableColumn("Last Seen") { device in
                if let lastSeen = device.lastSeenAt {
                    Text(lastSeen, format: .relative(presentation: .named))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            TableColumn("") { device in
                Button("Revoke", role: .destructive) {
                    if device.id == link.deviceID {
                        isConfirmingSelfRevoke = true
                    } else {
                        Task { await revoke(device.id) }
                    }
                }
            }
            .width(80)
        }
        .overlay(alignment: .bottom) {
            if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Pair a Device…", systemImage: "plus") { isPairing = true }
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
        .sheet(isPresented: $isPairing) {
            PairDeviceSheet(hive: hive, link: link) {
                Task { await load() }
            }
        }
        .confirmationDialog("Revoke this device?", isPresented: $isConfirmingSelfRevoke) {
            Button("Revoke", role: .destructive) {
                if let deviceID = link.deviceID { Task { await revoke(deviceID) } }
            }
        } message: {
            Text(selfRevokeMessage)
        }
        .task { await load() }
    }

    private static var thisDeviceLabel: String {
        #if os(macOS)
        "This Mac"
        #else
        "This Device"
        #endif
    }

    private var selfRevokeMessage: String {
        if hive.isOnThisMac {
            "Beekeeper signs out of \(hive.name) at once. You can pair again from this Mac."
        } else {
            "Beekeeper signs out of \(hive.name) at once, and can't manage it until it pairs again."
        }
    }

    private func load() async {
        do {
            devices = try await link.perform { try await $0.get(HiveEndpoint.devices) }
            failure = nil
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    private func revoke(_ deviceID: UUID) async {
        do {
            try await link.perform { try await $0.delete(HiveEndpoint.device(deviceID)) }
        } catch {
            failure = HiveLink.message(for: error)
            return
        }
        if deviceID == link.deviceID {
            link.forgetCredential()
        } else {
            await load()
        }
    }
}
