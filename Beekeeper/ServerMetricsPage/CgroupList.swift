#if os(iOS)
import SwiftUI

/// At iPhone width, container groups, containers or services as rows in order of CPU or memory, each
/// with its color on the charts, and the processes of the one tapped in a sheet.
struct CgroupList: View {
    let rows: [CgroupRow]
    let cgroups: CgroupHistory
    /// The server's process groups at the same moment.
    let processes: [ProcessRow]
    let order: MomentProcesses.Order
    @Binding var selection: CgroupRow.ID?

    var body: some View {
        List(sorted) { row in
            Button { selection = row.id } label: {
                CgroupListRow(
                    row: row,
                    order: order,
                    color: cgroups.color(name: row.groupName, composeProject: row.composeProject) ?? .gray
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .sheet(isPresented: isShowingProcesses) {
            if let selected = rows.first(where: { $0.id == selection }) {
                NavigationStack {
                    CgroupProcesses(cgroup: selected, processes: processes)
                        .padding(.horizontal)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selection = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var sorted: [CgroupRow] {
        switch order {
        case .cpu: rows.sorted { $0.cpuOrder > $1.cpuOrder }
        case .memory: rows.sorted { $0.memoryOrder > $1.memoryOrder }
        }
    }

    private var isShowingProcesses: Binding<Bool> {
        Binding { selection != nil } set: { if !$0 { selection = nil } }
    }
}
#endif
