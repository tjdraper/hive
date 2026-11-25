import HiveKit
import SwiftUI

/// The server's processes at the moment chosen on its charts: the sample nearest it, or that hour's
/// busiest groups once single samples have aged out. Its containers and services are a choice away.
struct MomentProcesses: View {
    enum Subject: String, CaseIterable, Identifiable {
        case processes = "Processes"
        case containers = "Containers"
        case services = "Services"

        var id: Self {
            self
        }
    }

    enum Order: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"

        var id: Self {
            self
        }
    }

    let link: HiveLink
    let serverID: UUID
    /// Seconds since 1970 on the server's clock.
    let moment: Date
    let processesHidden: Bool
    let onClose: () -> Void

    @State private var processes: ProcessMoment?
    @State private var failure: String?
    @State private var order = Order.cpu
    @State private var subject = Subject.processes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Picker("Show", selection: $subject) {
                        ForEach(Subject.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Spacer(minLength: 4)
                    Button("Close", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Close the processes")
                }
                if subject == .processes, let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Order", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            switch subject {
            case .processes: content
            case .containers: MomentCgroups(link: link, serverID: serverID, moment: moment, kind: .containers, order: order)
            case .services: MomentCgroups(link: link, serverID: serverID, moment: moment, kind: .services, order: order)
            }
        }
        .task(id: moment) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch processes {
        case .sample, .hour:
            list(processes.map(ProcessRow.rows) ?? [])
        case .notKept:
            ContentUnavailableView(
                "No Processes Kept",
                systemImage: "list.bullet.rectangle",
                description: Text(
                    processesHidden
                        ? "The server hides other users' processes from Scout."
                        : "Processes are kept for 14 days, and only while Scout reported."
                )
            )
        case nil:
            if let failure {
                ContentUnavailableView("Couldn't Read Processes", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func list(_ rows: [ProcessRow]) -> some View {
        List(sorted(rows)) { row in
            rowView(row)
        }
    }

    /// When the figures are from, since the nearest kept may be a little off the moment chosen.
    private var caption: String? {
        switch processes {
        case .sample(let takenAt, _):
            "At \(ProcessRow.time(takenAt)). Memory is each group's own, so it's approximate."
        case .hour(let startsAt, _):
            "The busiest over the hour from \(ProcessRow.time(startsAt)), on average, with their highest. "
                + "Single samples are kept for a day. Memory is approximate."
        case .notKept, nil:
            nil
        }
    }

    private func rowView(_ row: ProcessRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.placeText.isEmpty ? row.user : "\(row.user) · \(row.placeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    /// Scout sends the busiest by CPU and by memory, so each order's top is complete.
    private func sorted(_ rows: [ProcessRow]) -> [ProcessRow] {
        switch order {
        case .cpu: rows.sorted { $0.cpuOrder > $1.cpuOrder }
        case .memory: rows.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    private func load() async {
        processes = nil
        failure = nil
        do {
            let second = Int64(moment.timeIntervalSince1970.rounded(.down))
            processes = try await link.perform {
                try await $0.get(HiveEndpoint.processes(ofServer: serverID, at: second), as: ProcessMoment.self)
            }
        } catch is CancellationError {
            return
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}
