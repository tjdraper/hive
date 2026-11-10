import HiveKit
import SwiftUI

/// Where the job stands: its run going now, its last run and its next, with Run Now and Cancel.
struct JobStatusSection: View {
    let job: BackupJob
    let statuses: JobStatusStore

    @State private var failure: String?
    @State private var isSending = false

    private var status: JobStatus? {
        statuses.status(of: job.id)
    }

    var body: some View {
        Section("Status") {
            if let status {
                current(status)
                lastRun(status)
                if let next = status.nextRunAt {
                    LabeledContent("Next run") {
                        Text(next.spoken)
                    }
                }
                if let since = status.overdueSince {
                    Label {
                        Text("No complete snapshot since \(since.spoken). It's overdue.")
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                    }
                    .foregroundStyle(.orange)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .task(id: job) { await statuses.refresh(job.id) }
    }

    @ViewBuilder
    private func current(_ status: JobStatus) -> some View {
        HStack(alignment: .firstTextBaseline) {
            switch status.state {
            case .idle:
                Text("Not running")
                    .foregroundStyle(.secondary)
            case .waiting:
                Label("Waiting for other runs to finish", systemImage: "hourglass")
            case .running:
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.step?.summary ?? "Starting")
                    ProgressView(value: Double(status.current?.run.finishedParts ?? 0), total: Double(max(job.partCount, 1)))
                }
            }
            Spacer()
            if status.state == .idle {
                Button("Run Now") { send { _ = try await statuses.runNow(job.id) } }
                    .disabled(isSending)
            } else {
                Button("Cancel", role: .destructive) { send { try await statuses.cancel(job.id) } }
                    .disabled(isSending)
            }
        }
    }

    @ViewBuilder
    private func lastRun(_ status: JobStatus) -> some View {
        LabeledContent("Last run") {
            if let last = status.lastRun {
                RunOutcome(run: last.run)
            } else {
                Text("Never")
            }
        }
    }

    private func send(_ request: @escaping () async throws -> Void) {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                try await request()
                failure = nil
            } catch {
                failure = HiveLink.message(for: error)
            }
        }
    }
}

/// A finished run in a line: when, and whether it worked.
struct RunOutcome: View {
    let run: BackupRun

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label {
                Text((run.finishedAt ?? run.startedAt).spoken)
            } icon: {
                RunResultIcon(failure: run.failure)
            }
            if let failure = run.failure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct RunResultIcon: View {
    let failure: BackupFailure?

    var body: some View {
        switch failure {
        case nil:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Succeeded")
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cancelled")
        case .interrupted:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Interrupted")
        default:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Failed")
        }
    }
}

extension BackupJob {
    /// What a run backs up, each directory and database counting once.
    var partCount: Int {
        directories.count + databases.count
    }
}
