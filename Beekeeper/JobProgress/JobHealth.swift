import HiveKit
import SwiftUI

/// A job's standing in a word, for list rows. A server takes its jobs' most pressing.
enum JobHealth: Int, Comparable {
    case unknown
    case fine
    case waiting
    case overdue
    case failed
    case running

    init(_ status: JobStatus?) {
        guard let status else {
            self = .unknown
            return
        }
        if status.state == .running {
            self = .running
        } else if let failure = status.lastRun?.run.failure, failure != .cancelled {
            self = .failed
        } else if status.overdueSince != nil {
            self = .overdue
        } else if status.state == .waiting {
            self = .waiting
        } else {
            self = status.lastRun == nil ? .unknown : .fine
        }
    }

    init(jobs: [BackupJob], in statuses: JobStatusStore) {
        self = jobs.map { JobHealth(statuses.status(of: $0.id)) }.max() ?? .unknown
    }

    static func < (lhs: JobHealth, rhs: JobHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .unknown: "Not run yet"
        case .fine: "Backed up"
        case .waiting: "Waiting"
        case .overdue: "Overdue"
        case .failed: "Last run failed"
        case .running: "Running"
        }
    }
}

/// Nothing while all is well, so only what needs a look stands out.
struct JobHealthBadge: View {
    let health: JobHealth

    var body: some View {
        Group {
            switch health {
            case .unknown, .fine:
                EmptyView()
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .waiting:
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
            case .overdue:
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .help(health.label)
        .accessibilityLabel(health.label)
    }
}
