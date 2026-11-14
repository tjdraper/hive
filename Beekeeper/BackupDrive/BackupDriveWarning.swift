import HiveKit
import SwiftUI

/// Shown on the Hive's overview while backups can't be written: no drive chosen, or the chosen one
/// missing or unusable.
struct BackupDriveWarning: View {
    let state: BackupDriveState?
    let onOpenSettings: () -> Void

    var body: some View {
        if let state, let warning = Self.warning(for: state.chosen) {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(warning.title)
                            .font(.headline)
                        Text(warning.detail)
                            .foregroundStyle(.secondary)
                    }
                }
                if warning.offersSettings {
                    Button("Choose a Drive…", action: onOpenSettings)
                }
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

/// The backup drive as Hive last reported it. The overview keeps it, since a form runs nothing for a
/// section that isn't showing.
@Observable
final class BackupDriveWatch {
    /// Often enough that ejecting the drive shows on the overview soon after.
    private static let refreshInterval = Duration.seconds(15)

    private(set) var state: BackupDriveState?

    func watch(_ link: HiveLink) async {
        while !Task.isCancelled {
            if let loaded: BackupDriveState = try? await link.perform({ try await $0.get(HiveEndpoint.backupDrive) }) {
                state = loaded
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}
