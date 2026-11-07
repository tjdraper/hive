import HiveKit
import SwiftUI

/// Shown on the Hive's overview while backups can't be written: no drive chosen, or the chosen one
/// missing or unusable.
struct BackupDriveWarning: View {
    let link: HiveLink
    let onOpenSettings: () -> Void

    /// Often enough that ejecting the drive shows here soon after.
    private static let refreshInterval = Duration.seconds(15)

    @State private var state: BackupDriveState?

    var body: some View {
        Group {
            if let state, let warning = Self.warning(for: state.chosen) {
                GroupBox {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(warning.title)
                                .font(.headline)
                            Text(warning.detail)
                                .foregroundStyle(.secondary)
                            if warning.offersSettings {
                                Button("Choose a Drive…", action: onOpenSettings)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(4)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                if let loaded: BackupDriveState = try? await link.perform({ try await $0.get(HiveEndpoint.backupDrive) }) {
                    state = loaded
                }
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    private struct Warning {
        let title: String
        let detail: String
        let offersSettings: Bool
    }

    private static func warning(for chosen: ChosenBackupDrive?) -> Warning? {
        guard let chosen else {
            return Warning(
                title: "No backup drive",
                detail: "Hive can't back anything up until a drive is chosen in Settings.",
                offersSettings: true
            )
        }
        guard let problem = chosen.problem else { return nil }
        if problem == .notMounted {
            return Warning(
                title: "The backup drive isn't connected",
                detail: "“\(chosen.drive.name)” isn't mounted on the Hive's Mac. Backups fail until it's connected again.",
                offersSettings: false
            )
        }
        return Warning(
            title: "Hive can't write to the backup drive",
            detail: "“\(chosen.drive.name)”: \(problem.chosenDriveMessage)",
            offersSettings: true
        )
    }
}
