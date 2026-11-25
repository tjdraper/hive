import HiveKit
import SwiftUI

/// The server's container groups or services at the moment chosen on its charts, beside its processes:
/// the sample nearest it, or that hour's busiest once single samples have aged out.
struct MomentCgroups: View {
    let link: HiveLink
    let serverID: UUID
    let moment: Date
    let kind: ContainersPage.Kind
    let order: MomentProcesses.Order

    @State private var figures: CgroupMoment?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            content
        }
        .task(id: moment) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch figures {
        case .sample, .hour:
            if rows.isEmpty {
                ContentUnavailableView(kind == .containers ? "No Containers" : "No Services", systemImage: "shippingbox")
            } else {
                List(rows) { row in
                    rowView(row)
                }
            }
        case .notKept:
            ContentUnavailableView(
                "Nothing Kept",
                systemImage: "shippingbox",
                description: Text("Containers and services are kept for 90 days, and only while Scout reported.")
            )
        case nil:
            if let failure {
                ContentUnavailableView(
                    "Couldn't Read \(kind.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Scout sends only the busiest, so the server's count goes beside them.
    private var caption: String? {
        switch (figures, kind) {
        case (.sample(let takenAt, let containerCount, _, let containers, _), .containers):
            containers.reduce(0) { $0 + $1.containerCount } < containerCount
                ? "At \(ProcessRow.time(takenAt)). \(containerCount) running; a group counts only those among the busiest."
                : "At \(ProcessRow.time(takenAt)). \(containerCount) running."
        case (.sample(let takenAt, _, let serviceCount, _, _), .services):
            "At \(ProcessRow.time(takenAt)). \(serviceCount) running. Includes work too brief for the process lists."
        case (.hour(let startsAt, _, _), _):
            "The busiest over the hour from \(ProcessRow.time(startsAt)), on average, with their highest."
        case (.notKept, _), (nil, _):
            nil
        }
    }

    private var rows: [CgroupRow] {
        let rows: [CgroupRow] = switch (figures, kind) {
        case (.sample(_, _, _, let groups, _), .containers), (.hour(_, let groups, _), .containers): CgroupRow.groups(groups)
        case (.sample(_, _, _, _, let services), .services), (.hour(_, _, let services), .services): CgroupRow.services(services)
        case (.notKept, _), (nil, _): []
        }
        return switch order {
        case .cpu: rows.sorted { $0.cpuOrder > $1.cpuOrder }
        case .memory: rows.sorted { $0.memoryOrder > $1.memoryOrder }
        }
    }

    private func rowView(_ row: CgroupRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.containerCount.map { $0 > 1 ? "\(row.name) ×\($0)" : row.name } ?? row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.cpuText) CPU")
                    .fontWeight(order == .cpu ? .semibold : .regular)
                Text(row.memoryText)
                    .font(.caption)
                    .fontWeight(order == .memory ? .semibold : .regular)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        figures = nil
        failure = nil
        do {
            let second = Int64(moment.timeIntervalSince1970.rounded(.down))
            figures = try await link.perform {
                try await $0.get(HiveEndpoint.containers(ofServer: serverID, at: second), as: CgroupMoment.self)
            }
        } catch is CancellationError {
            return
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}
