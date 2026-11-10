import HiveKit
import SwiftUI

/// The server's quota, set in its editor, beside what its snapshots take now, and deleting them all.
struct ServerQuotaSection: View {
    let link: HiveLink
    let servers: ServerList
    let server: Server

    @State private var space: ServerSpace?
    @State private var deletion: SnapshotDeletionRequest?

    var body: some View {
        Section("Space") {
            LabeledContent("Quota", value: server.quotaBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "No limit")
            LabeledContent("Uses now", value: ServerSpace.describe(space))
            if space?.usedBytes != 0 {
                Button("Delete All Snapshots…", systemImage: "trash", role: .destructive) {
                    deletion = SnapshotDeletionRequest(scope: .server(id: server.id), name: server.name)
                }
            }
        }
        // After a run or a removal too, which change what the server's snapshots take.
        .task(id: [server.quotaBytes, Int64(servers.statuses.logRevision)]) {
            space = try? await servers.space(of: server.id)
        }
        .snapshotDeletion($deletion, link: link)
    }
}
