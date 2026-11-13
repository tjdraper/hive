import HiveKit
import SwiftUI

/// The volumes mounted on the Hive's Mac, to choose the backup drive from.
struct BackupDriveChooser: View {
    let link: HiveLink
    let state: BackupDriveState
    let onChosen: (BackupDriveState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: UUID?
    @State private var isSaving = false
    @State private var failure: String?

    var body: some View {
        SheetLayout(
            title: "Choose the Backup Drive",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(
                title: "Use This Drive",
                isDisabled: choice == nil || choice == state.chosen?.drive.volumeUUID || isSaving
            ) { Task { await choose() } }
        ) {
            chooser
        }
        #if os(macOS)
        .frame(minWidth: 480)
        #endif
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            Text("Choose the Backup Drive")
                .font(.headline)
            #endif
            Text("Only a case-sensitive APFS volume attached to the Hive's Mac can hold backups.")
                .foregroundStyle(.secondary)

            List(state.volumes, id: \.volumeUUID, selection: $choice) { volume in
                VolumeRow(volume: volume, isChosen: volume.volumeUUID == state.chosen?.drive.volumeUUID)
                    .selectionDisabled(volume.problem != nil)
            }
            .frame(minHeight: 180)

            if state.chosen != nil {
                Text("Snapshots already on the current drive stay there. New ones go on the drive you choose.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private func choose() async {
        guard let choice else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let chosen: BackupDriveState = try await link.perform {
                try await $0.put(HiveEndpoint.backupDrive, body: BackupDriveChoice(volumeUUID: choice))
            }
            onChosen(chosen)
            dismiss()
        } catch let refused as HiveRequestError {
            failure = (try? JSONDecoder().decode(BackupDriveRefusal.self, from: refused.body))
                .map { "Hive can't use it: \($0.problem.volumeMessage.lowercased())." }
                ?? HiveLink.message(for: refused)
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

private struct VolumeRow: View {
    let volume: BackupVolume
    let isChosen: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "externaldrive")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(volume.name)
                    if isChosen {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let problem = volume.problem {
                Text(problem.volumeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(volume.problem == nil ? 1 : 0.6)
        .padding(.vertical, 2)
    }

    private var details: String {
        let free = volume.availableBytes.formatted(.byteCount(style: .file))
        let total = volume.totalBytes.formatted(.byteCount(style: .file))
        return "\(volume.format) · \(free) free of \(total)"
    }
}
