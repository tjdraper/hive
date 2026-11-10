import HiveKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The job's snapshots on the backup drive, newest first, with what each takes of its own, deleting
/// them, and on the Hive's Mac, a way to find them in Finder. A removed job's are shown the same way.
struct JobSnapshotsSection: View {
    let hive: KnownHive
    let link: HiveLink
    let jobID: UUID
    let jobName: String
    let statuses: JobStatusStore

    @State private var snapshots: JobSnapshots?
    @State private var failure: String?
    @State private var deletion: SnapshotDeletionRequest?

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
                    SnapshotRow(snapshot: snapshot, folder: snapshotFolder(snapshot, in: snapshots)) {
                        deletion = SnapshotDeletionRequest(scope: .snapshot(snapshot), name: jobName)
                    }
                }
                if deletable > 1 {
                    Button("Delete All Snapshots…", systemImage: "trash", role: .destructive) {
                        deletion = SnapshotDeletionRequest(scope: .job(id: jobID, count: deletable), name: jobName)
                    }
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
        .snapshotDeletion($deletion, link: link) { Task { await load() } }
    }

    /// Those not being deleted already.
    private var deletable: Int {
        snapshots?.snapshots.count { $0.state != .removing } ?? 0
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
            snapshots = try await link.perform { try await $0.get(HiveEndpoint.snapshots(ofJob: jobID)) }
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
    /// Nil where it can't be deleted from, such as in a preview.
    var onDelete: (() -> Void)?

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
            if let onDelete, snapshot.state != .removing {
                Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete this snapshot")
            }
        }
    }
}
