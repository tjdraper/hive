import HiveKit
import SwiftUI

/// The server's quota, set in its editor, beside what its snapshots take now.
struct ServerQuotaSection: View {
    let servers: ServerList
    let server: Server

    @State private var space: ServerSpace?

    var body: some View {
        Section("Space") {
            LabeledContent("Quota", value: server.quotaBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "No limit")
            LabeledContent("Uses now", value: ServerSpace.describe(space))
        }
        .task(id: server.quotaBytes) {
            space = try? await servers.space(of: server.id)
        }
    }
}
