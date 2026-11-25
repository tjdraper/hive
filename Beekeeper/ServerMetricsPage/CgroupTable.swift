import SwiftUI

/// Container groups, containers or services in sortable columns, each with its color on the charts.
struct CgroupTable: View {
    let rows: [CgroupRow]
    let kind: ContainersPage.Kind
    let cgroups: CgroupHistory
    @Binding var selection: CgroupRow.ID?
    @Binding var sortOrder: [KeyPathComparator<CgroupRow>]

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cgroups.color(name: row.groupName, composeProject: row.composeProject) ?? .gray)
                        .frame(width: 9, height: 9)
                    Text(row.name)
                        .truncationMode(.middle)
                }
            }
            .width(min: 140, ideal: 220)
            if kind == .containers {
                TableColumn("What", value: \.detail) { row in
                    Text(row.detail)
                        .foregroundStyle(.secondary)
                        .truncationMode(.tail)
                }
            }
            TableColumn("CPU", value: \.cpuOrder) { row in
                Text(row.cpuText)
                    .monospacedDigit()
            }
            TableColumn("Memory", value: \.memoryOrder) { row in
                Text(row.memoryText)
                    .monospacedDigit()
            }
            TableColumn("Processes", value: \.processOrder) { row in
                Text(row.processes.map { "\($0)" } ?? "—")
                    .monospacedDigit()
            }
            .width(ideal: 70)
        }
    }
}

/// The processes running in the group, container or service selected in a `CgroupTable`.
struct CgroupProcesses: View {
    let cgroup: CgroupRow
    /// The server's process groups at the same moment.
    let processes: [ProcessRow]

    var body: some View {
        // Scout sends only the busiest process groups, so these are the selected one's among them.
        let rows = processes.filter(cgroup.holds).sorted { $0.cpuOrder > $1.cpuOrder }
        VStack(alignment: .leading, spacing: 6) {
            Text("Processes in \(cgroup.name)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Those among the server's busiest. Memory is approximate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                ContentUnavailableView("None Among the Busiest", systemImage: "list.bullet.rectangle")
            } else {
                List(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(row.user)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(row.cpuText) CPU")
                            Text(row.memoryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
