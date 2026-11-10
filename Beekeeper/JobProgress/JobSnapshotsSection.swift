import HiveKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The job's snapshots on the backup drive, newest first, with what each takes of its own, and on the
/// Hive's Mac, a way to find them in Finder.
struct JobSnapshotsSection: View {
    let hive: KnownHive
    let link: HiveLink
    let job: BackupJob
    let statuses: JobStatusStore

    @State private var snapshots: JobSnapshots?
    @State private var failure: String?

    var body: some View {
        Section {
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let snapshots {
                if snapshots.snapshots.isEmpty {
                    Text("No snapshots yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshots.snapshots) { snapshot in
                    SnapshotRow(snapshot: snapshot, folder: snapshotFolder(snapshot, in: snapshots))
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            HStack {
                Text("Snapshots")
                Spacer()
                if let used = snapshots?.usedBytes {
                    Text("\(used.formatted(.byteCount(style: .file))) in all")
                        .foregroundStyle(.secondary)
                        .fontWeight(.regular)
                }
            }
        } footer: {
            if let snapshots, !snapshots.snapshots.isEmpty {
                footer(snapshots)
            }
        }
        .task(id: statuses.logRevision) { await load() }
    }

    private func footer(_ snapshots: JobSnapshots) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Each size is what the snapshot alone takes. Files it shares with others are counted once, in the total.")
            if snapshots.folderPath != nil, hive.isOnThisMac {
                Text(
                    "Copy files out of a snapshot before opening them. A file is shared by every snapshot that has it, "
                        + "so changing it in place changes it in all of them."
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Only on the Hive's Mac, where the folder is.
    private func snapshotFolder(_ snapshot: SnapshotSummary, in snapshots: JobSnapshots) -> URL? {
        guard hive.isOnThisMac, snapshot.state != .removing, let path = snapshots.folderPath else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory).appending(path: snapshot.folder, directoryHint: .isDirectory)
    }

    private func load() async {
        do {
            snapshots = try await link.perform { try await $0.get(HiveEndpoint.snapshots(ofJob: job.id)) }
            failure = nil
        } catch where !Task.isCancelled {
            failure = HiveLink.message(for: error)
        } catch {
            // A newer load replaced it.
        }
    }
}

struct SnapshotRow: View {
    let snapshot: SnapshotSummary
    let folder: URL?

    var body: some View {
        HStack {
            Text(snapshot.date, format: .dateTime.year().month().day().hour().minute())
            switch snapshot.state {
            case .complete:
                EmptyView()
            case .partial:
                Text("Incomplete")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Being written, or left by a run that failed. The next run carries on with it.")
            case .removing:
                Text("Being removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let bytes = snapshot.freesBytes {
                Text(bytes.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            #if os(macOS)
            if let folder {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            #endif
        }
    }
}
