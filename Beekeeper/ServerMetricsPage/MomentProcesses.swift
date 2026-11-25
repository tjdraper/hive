import HiveKit
import SwiftUI

/// The server's processes at the moment chosen on its charts: the sample nearest it, or that hour's
/// busiest groups once single samples have aged out.
struct MomentProcesses: View {
    enum Order: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"

        var id: Self {
            self
        }
    }

    /// A group as the list shows it, from a sample or an hour.
    private struct Row: Identifiable {
        let command: String
        let user: String
        let count: Int
        let cpuCores: Double?
        let memoryBytes: UInt64
        /// The hour's highest, beside its average.
        var highestCPUCores: Double?
        var highestMemoryBytes: UInt64?

        var id: String {
            "\(command) \(user)"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Processes")
                        .font(.headline)
                    Spacer()
                    Button("Close", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Close the processes")
                }
                if let caption {
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
            content
        }
        .task(id: moment) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch processes {
        case .sample(_, let groups):
            list(
                groups.map {
                    Row(command: $0.command, user: $0.user, count: $0.count, cpuCores: $0.cpuCores, memoryBytes: $0.ownMemoryBytes)
                }
            )
        case .hour(_, let groups):
            list(
                groups.map {
                    Row(
                        command: $0.command,
                        user: $0.user,
                        count: $0.highestCount,
                        cpuCores: $0.averageCPUCores,
                        memoryBytes: $0.averageOwnMemoryBytes,
                        highestCPUCores: $0.highestCPUCores,
                        highestMemoryBytes: $0.highestOwnMemoryBytes
                    )
                }
            )
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

    private func list(_ rows: [Row]) -> some View {
        List(sorted(rows)) { row in
            rowView(row)
        }
    }

    /// When the figures are from, since the nearest kept may be a little off the moment chosen.
    private var caption: String? {
        switch processes {
        case .sample(let takenAt, _):
            "At \(Self.time(takenAt)). Memory is each group's own, so it's approximate."
        case .hour(let startsAt, _):
            "The busiest over the hour from \(Self.time(startsAt)), on average, with their highest. "
                + "Single samples are kept for a day. Memory is approximate."
        case .notKept, nil:
            nil
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.count > 1 ? "\(row.command) ×\(row.count)" : row.command)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.user)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.cores(row.cpuCores, highest: row.highestCPUCores))
                    .fontWeight(order == .cpu ? .semibold : .regular)
                Text(Self.bytes(row.memoryBytes, highest: row.highestMemoryBytes))
                    .font(.caption)
                    .fontWeight(order == .memory ? .semibold : .regular)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Scout sends the busiest by CPU and by memory, so each order's top is complete.
    private func sorted(_ rows: [Row]) -> [Row] {
        switch order {
        case .cpu: rows.sorted { ($0.cpuCores ?? 0) > ($1.cpuCores ?? 0) }
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

    /// A share of one core, so 2 busy cores read 200%.
    private static func cores(_ cores: Double?, highest: Double?) -> String {
        guard let cores else { return "— CPU" }
        let average = cores.formatted(.percent.precision(.fractionLength(0)))
        guard let highest else { return "\(average) CPU" }
        return "\(average) CPU, up to \(highest.formatted(.percent.precision(.fractionLength(0))))"
    }

    private static func bytes(_ bytes: UInt64, highest: UInt64?) -> String {
        let average = Int64(clamping: bytes).formatted(.byteCount(style: .memory))
        guard let highest else { return average }
        return "\(average), up to \(Int64(clamping: highest).formatted(.byteCount(style: .memory)))"
    }

    private static func time(_ second: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(second)).formatted(date: .abbreviated, time: .standard)
    }
}
