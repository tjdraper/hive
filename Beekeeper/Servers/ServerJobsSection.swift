import HiveKit
import SwiftUI

/// The server's backup jobs, each opening its own page, and adding another.
struct ServerJobsSection: View {
    let jobs: [BackupJob]
    let statuses: JobStatusStore
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
                        JobHealthBadge(health: JobHealth(statuses.status(of: job.id)))
                        Text(job.times.map(\.formatted).formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button("Add Job…", systemImage: "plus", action: onAddJob)
        } header: {
            Text("Backup Jobs")
        }
    }
}
