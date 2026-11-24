import HiveKit
import SwiftUI

/// Says when servers' Scouts are out of date, and updates every one Hive can reach over SSH, one after
/// another, listing those it couldn't and why. The view holding it loads `outOfDate` with
/// `outOfDate(_:link:)`: this one shows nothing until a Scout is out of date, and a view showing nothing
/// never runs its tasks.
struct UpdateAllScouts: View {
    let link: HiveLink
    @Binding var outOfDate: [Server]

    private struct NotUpdated: Identifiable {
        let id: UUID
        let name: String
        let reason: String
    }

    @State private var updating: Server?
    @State private var updatedCount: Int?
    @State private var notUpdated: [NotUpdated] = []

    var body: some View {
        // One row, since a Form loses track of which row is which when rows come and go beside a ForEach.
        if updating != nil || !outOfDate.isEmpty || updatedCount != nil {
            VStack(alignment: .leading, spacing: 8) { rows }
        }
    }

    @ViewBuilder private var rows: some View {
        if let updating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(ScoutAction.update.progress(on: updating))
                    .foregroundStyle(.secondary)
            }
        } else if !outOfDate.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Label(summary, systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Update All") { Task { await updateAll() } }
            }
        }
        if let updatedCount, updating == nil {
            results(updatedCount)
        }
    }

    private var summary: String {
        guard outOfDate.count > 1 else { return "The Scout on “\(outOfDate[0].name)” is out of date." }
        return "\(outOfDate.count) servers' Scouts are out of date."
    }

    @ViewBuilder private func results(_ count: Int) -> some View {
        if count > 0 {
            Label(count == 1 ? "Updated 1 Scout." : "Updated \(count) Scouts.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        ForEach(notUpdated) { server in
            Label("Didn't update “\(server.name)”: \(server.reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The servers whose Scout has an update.
    static func outOfDate(_ servers: [Server], link: HiveLink) async -> [Server] {
        var found: [Server] = []
        for server in servers {
            let state: ServerMetricsState? = try? await link.perform { try await $0.get(HiveEndpoint.metrics(ofServer: server.id)) }
            if state?.scout?.update != nil { found.append(server) }
        }
        return found
    }

    private func updateAll() async {
        updatedCount = nil
        notUpdated = []
        var count = 0
        let servers = outOfDate
        for server in servers {
            updating = server
            let ssh = ScoutOverSSH(link: link, server: server)
            guard ssh.canCheck else {
                let reason = "Hive can't sign in to it. Update it with the command on its page."
                notUpdated.append(NotUpdated(id: server.id, name: server.name, reason: reason))
                continue
            }
            if await ssh.perform(.update) {
                count += 1
            } else {
                let reason = ssh.outcome?.message ?? "it didn't say why."
                notUpdated.append(NotUpdated(id: server.id, name: server.name, reason: reason))
            }
        }
        updating = nil
        updatedCount = count
        outOfDate = await Self.outOfDate(servers, link: link)
    }
}
