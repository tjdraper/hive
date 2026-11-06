import HiveKit
import SwiftUI

/// Every change made to the Hive, newest first.
struct AuditLogView: View {
    let link: HiveLink

    @State private var entries: [AuditEntry] = []
    @State private var nextBefore: Int64?
    @State private var failure: String?

    var body: some View {
        List {
            ForEach(entries) { entry in
                AuditEntryRow(entry: entry)
            }
            if let nextBefore {
                Button("Show Older") {
                    Task { await load(before: nextBefore) }
                }
            }
        }
        .overlay {
            if let failure {
                ContentUnavailableView("Couldn't Load the Audit Log", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else if entries.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "list.bullet.rectangle")
            }
        }
        .task { await load(before: nil) }
        .refreshable { await load(before: nil) }
    }

    private func load(before: Int64?) async {
        let path = before.map { "\(HiveEndpoint.auditLog)?before=\($0)" } ?? HiveEndpoint.auditLog
        do {
            let page: AuditLogPage = try await link.perform { try await $0.get(path) }
            entries = before == nil ? page.entries : entries + page.entries
            nextBefore = page.nextBefore
            failure = nil
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

private struct AuditEntryRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.event.summary)
            HStack(spacing: 4) {
                Text(entry.deviceName)
                Text("·")
                Text(entry.date, format: .dateTime)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
