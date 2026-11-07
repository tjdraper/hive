import HiveKit
import SwiftUI

/// Hive's key for a server, with the line to add to the server's `authorized_keys`, limited to the
/// Hive Mac's addresses the person chooses.
struct AuthorizedKeySetup: View {
    let link: HiveLink
    let server: Server

    private enum Limit: Hashable {
        case macAddresses
        case anywhere
    }

    @State private var key: ServerSSHKey?
    @State private var limit = Limit.anywhere
    @State private var acceptedFrom: Set<String> = []
    @State private var isMissing = false
    @State private var failure: String?

    var body: some View {
        if let key, !key.macAddresses.isEmpty {
            limitSection(key)
        }
        Section("Add Hive's Key to the Server") {
            if let key {
                keyRows(key)
            } else if isMissing {
                Text("This server has no key of Hive's yet.")
                Button("Make Hive's Key") { Task { await makeKey() } }
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task { await load() }
    }

    private func limitSection(_ key: ServerSSHKey) -> some View {
        Section {
            Picker("Accept Hive's key", selection: $limit) {
                Text("Only from these addresses of the Hive's Mac").tag(Limit.macAddresses)
                Text("From any address").tag(Limit.anywhere)
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.radioGroup)
            #else
            .pickerStyle(.inline)
            #endif
            if limit == .macAddresses {
                ForEach(Self.tailscaleFirst(key.macAddresses), id: \.address) { address in
                    Toggle(address.label, isOn: accepts(address.address))
                    #if os(macOS)
                        .toggleStyle(.checkbox)
                        .padding(.leading, 20)
                    #endif
                }
            }
        } header: {
            Text("Where the Server Accepts Hive's Key")
        } footer: {
            Text(
                "Hive connects to the server over SSH. Limited to the Hive's Mac's addresses, the server turns Hive's key "
                    + "away from anywhere else, so a copy of it is no use. Choose any address when the server sees Hive's "
                    + "connections come from another address, such as through a port forward."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func keyRows(_ key: ServerSSHKey) -> some View {
        Text("Add this line to \(authorizedKeysPath) on \(server.connection.host), so Hive can sign in as \(server.connection.user).")
        if let line = line(for: key) {
            CommandText(text: line)
        } else {
            Text("Choose at least one address above.")
                .foregroundStyle(.orange)
        }
        LabeledContent("Fingerprint") {
            Text(key.fingerprint)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    /// Nil while limited to the Mac's addresses with none chosen, which would otherwise read as no limit.
    private func line(for key: ServerSSHKey) -> String? {
        guard limit == .macAddresses, !key.macAddresses.isEmpty else { return key.authorizedKeysLine() }
        let chosen = key.macAddresses.map(\.address).filter(acceptedFrom.contains)
        return chosen.isEmpty ? nil : key.authorizedKeysLine(acceptingFrom: chosen)
    }

    private var authorizedKeysPath: String {
        let user = server.connection.user
        return user == "root" ? "/root/.ssh/authorized_keys" : "~\(user)/.ssh/authorized_keys"
    }

    private func accepts(_ address: String) -> Binding<Bool> {
        Binding {
            acceptedFrom.contains(address)
        } set: { isOn in
            if isOn { acceptedFrom.insert(address) } else { acceptedFrom.remove(address) }
        }
    }

    private static func tailscaleFirst(_ addresses: [NetworkInterfaceAddress]) -> [NetworkInterfaceAddress] {
        addresses.filter(\.isTailscale) + addresses.filter { !$0.isTailscale }
    }

    private func load() async {
        do {
            show(try await link.perform { try await $0.get(HiveEndpoint.sshKey(onServer: server.id)) })
        } catch let refused as HiveRequestError where refused.status == 404 {
            isMissing = true
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    /// Only for a server added before Hive made keys. Replacing a key is a confirmed action (D4).
    private func makeKey() async {
        do {
            show(try await link.perform { try await $0.post(HiveEndpoint.sshKey(onServer: server.id)) })
            isMissing = false
        } catch {
            failure = HiveLink.message(for: error)
        }
    }

    /// Hive reaches servers over the tailnet, so its Tailscale addresses are the ones a server sees.
    private func show(_ loaded: ServerSSHKey) {
        if key == nil {
            acceptedFrom = Set(loaded.macAddresses.filter(\.isTailscale).map(\.address))
            limit = acceptedFrom.isEmpty ? .anywhere : .macAddresses
        }
        key = loaded
    }
}

extension NetworkInterfaceAddress {
    /// Tailscale gives each machine an address from 100.64.0.0/10 and fd7a:115c:a1e0::/48.
    var isTailscale: Bool {
        if address.lowercased().hasPrefix("fd7a:115c:a1e0:") { return true }
        let octets = address.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 100 && (64 ... 127).contains(octets[1])
    }

    var label: String {
        isTailscale ? "\(address) (Tailscale)" : "\(address) (\(interface))"
    }
}
