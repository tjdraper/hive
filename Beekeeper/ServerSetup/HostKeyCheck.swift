import HiveKit
import SwiftUI

/// Scanning a server's host key and confirming it once the person has checked the fingerprint. Hive
/// connects to a server only with a confirmed key, so nothing between them can stand in for it.
struct HostKeyCheck: View {
    let link: HiveLink
    let servers: ServerList
    let server: Server
    var scansOnAppear = false

    private enum Scan {
        case scanning
        case found(HostKeyFingerprint)
        case failed(String)
    }

    @State private var scan: Scan?
    @State private var isConfirming = false
    @State private var failure: String?

    var body: some View {
        Section("Host Key") {
            if let confirmed = server.confirmedHostKey {
                LabeledContent("Confirmed \(confirmed.typeName) key") {
                    FingerprintText(fingerprint: confirmed.fingerprint)
                }
            } else {
                unconfirmed
            }
        }
        .task {
            if scansOnAppear, server.confirmedHostKey == nil { await scanNow() }
        }
    }

    @ViewBuilder private var unconfirmed: some View {
        switch scan {
        case nil:
            HStack {
                Text("Not confirmed yet. Hive won't connect until it is.")
                Spacer()
                Button("Scan Host Key") { Task { await scanNow() } }
            }
        case .scanning:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Asking \(server.connection.host) for its host key…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Scan Again") { Task { await scanNow() } }
            }
        case .found(let key):
            Text(
                "\(server.connection.host) showed this \(key.typeName) key. Before confirming it, check that it matches "
                    + "the server's own, so Hive never trusts a machine standing in for the server."
            )
            FingerprintText(fingerprint: key.fingerprint)
                .font(.title3.monospaced())
            Text("On the server, this shows its fingerprint:")
                .foregroundStyle(.secondary)
            CommandText(text: "ssh-keygen -lf /etc/ssh/\(key.hostKeyFile)")
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Scan Again") { Task { await scanNow() } }
                Spacer()
                Button("It Matches, Confirm") { Task { await confirm(key) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
            }
        }
    }

    private func scanNow() async {
        scan = .scanning
        failure = nil
        do {
            let result: HostKeyScanResult = try await link.perform { try await $0.post(HiveEndpoint.hostKeyScan(onServer: server.id)) }
            switch result {
            case .found(let key): scan = .found(key)
            case .failed(let reason): scan = .failed(reason.message(for: server))
            }
        } catch {
            scan = .failed(HiveLink.message(for: error))
        }
    }

    private func confirm(_ key: HostKeyFingerprint) async {
        isConfirming = true
        defer { isConfirming = false }
        do {
            let confirmed: Server = try await link.perform {
                try await $0.put(HiveEndpoint.hostKey(onServer: server.id), body: HostKeyConfirmation(fingerprint: key.fingerprint))
            }
            servers.update(confirmed)
            scan = nil
        } catch let refused as HiveRequestError where refused.status == 409 {
            let reason = try? JSONDecoder().decode(HostKeyConfirmationRefusal.self, from: refused.body).reason
            failure = switch reason {
            case .fingerprintMismatch: "The server's key changed since the scan. Scan again and check the new one."
            case .noScan, nil: "The scan is too old, or the server's connection changed since. Scan again."
            }
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

private struct FingerprintText: View {
    let fingerprint: String

    var body: some View {
        Text(fingerprint)
            .monospaced()
            .textSelection(.enabled)
    }
}

extension HostKeyFingerprint {
    /// As `ssh-keygen -l` names the type.
    var typeName: String {
        switch keyType {
        case "ssh-ed25519": "ED25519"
        case "ssh-rsa": "RSA"
        default: keyType.hasPrefix("ecdsa-") ? "ECDSA" : keyType
        }
    }

    /// Where OpenSSH keeps a server's public host key of this type, under `/etc/ssh`.
    var hostKeyFile: String {
        "ssh_host_\(typeName.lowercased())_key.pub"
    }
}
