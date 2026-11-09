import HiveKit
import SwiftUI

/// The server's backup jobs, each opening its own page, and adding another.
struct ServerJobsSection: View {
    let jobs: [BackupJob]
    let onAddJob: () -> Void
    let onSelectJob: (UUID) -> Void

    var body: some View {
        Section {
            if jobs.isEmpty {
                Text("No backup jobs yet. Add one for each site on this server.")
                    .foregroundStyle(.secondary)
            }
            ForEach(jobs) { job in
                Button { onSelectJob(job.id) } label: {
                    HStack {
                        Label(job.name, systemImage: "archivebox")
                        Spacer()
                        Text(job.times.map(\.formatted).formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Backup Jobs")
                Spacer()
                Button("Add Job…", action: onAddJob)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
    }
}
