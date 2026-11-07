import HiveKit
import SwiftUI

/// The drive Hive writes snapshots to, in the Hive's settings.
struct BackupDriveSection: View {
    let link: HiveLink

    @State private var state: BackupDriveState?
    @State private var failure: String?
    @State private var isChoosing = false

    var body: some View {
        Section {
            if let state {
                chosen(state.chosen)
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Backup Drive")
        } footer: {
            Text(
                "Hive writes snapshots to a drive attached to its Mac, formatted APFS (Case-sensitive). Linux servers "
                    + "can hold “Foo.jpg” and “foo.jpg” side by side, and a drive that ignores case would keep only one."
            )
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isChoosing) {
            if let state {
                BackupDriveChooser(link: link, state: state) { self.state = $0 }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func chosen(_ chosen: ChosenBackupDrive?) -> some View {
        LabeledContent("Drive") {
            HStack(spacing: 12) {
                Text(chosen?.drive.name ?? "None chosen")
                    .foregroundStyle(.secondary)
                Button(chosen == nil ? "Choose…" : "Change…") { isChoosing = true }
            }
        }
        if let problem = chosen?.problem {
            Label(problem.chosenDriveMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func load() async {
        do {
            state = try await link.perform { try await $0.get(HiveEndpoint.backupDrive) }
            failure = nil
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

extension BackupDriveProblem {
    /// About the drive Hive already writes to.
    var chosenDriveMessage: String {
        switch self {
        case .notMounted: "Not connected. Backups fail until it's back."
        case .notWritable: "Hive can't write to it. It may need Full Disk Access."
        case .readOnly: "Mounted read-only, so backups fail."
        case .belongsToAnotherHive: "Its Hive folder now belongs to another Hive."
        case .notAPFS, .notCaseSensitive, .startupDisk, .notLocal, .folderInUse: "Hive can't use it any more."
        }
    }

    /// Why a volume can't be chosen.
    var volumeMessage: String {
        switch self {
        case .notMounted: "Not connected"
        case .notAPFS: "Not APFS"
        case .notCaseSensitive: "Not case-sensitive"
        case .readOnly: "Read-only"
        case .startupDisk: "The Mac's startup disk"
        case .notLocal: "Not attached to the Mac"
        case .belongsToAnotherHive: "Holds another Hive's backups"
        case .folderInUse: "Its “Hive” folder holds other files"
        case .notWritable: "Hive can't write to it"
        }
    }
}
