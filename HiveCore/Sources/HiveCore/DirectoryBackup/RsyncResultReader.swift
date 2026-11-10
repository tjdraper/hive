import Foundation
import HiveKit

/// What a directory on the server held when Hive listed its top.
enum SourceListing: Equatable {
    case hasFiles
    case empty
    case failed(BackupFailure)
}

struct PullStatistics: Equatable {
    var filesTransferred = 0
    var bytesTransferred: Int64 = 0
    var bytesReceived: Int64 = 0
}

struct PullOutcome: Equatable {
    /// Nil when it succeeded, with or without vanished files.
    let failure: BackupFailure?
    let vanishedFiles: Bool
    let statistics: PullStatistics
}

/// Reads rsync's exit status and output. Its messages can name files, so they're only matched here,
/// never logged.
enum RsyncResultReader {
    /// The connection closed in the middle of rsync's protocol.
    static let protocolStreamStatus: Int32 = 12
    static let interruptedStatus: Int32 = 20
    /// Some files or attributes weren't copied.
    static let partialTransferStatus: Int32 = 23
    /// Files disappeared on the server while rsync was copying them.
    static let vanishedFilesStatus: Int32 = 24
    static let timeoutStatus: Int32 = 30

    private static let missingSourceMessages = ["No such file or directory (2)", "Not a directory (20)"]
    private static let unreadableSourceMessage = "Permission denied (13)"

    static func listing(in result: ChildProcess.Result) -> SourceListing {
        guard result.status == 0 else { return .failed(failure(in: result)) }
        let output = String(bytes: result.standardOutput, encoding: .utf8) ?? ""
        // Each line is the mode, size, date, time and name. The folder itself is listed as `.`.
        let names = output.split(separator: "\n").map { line in
            line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).last ?? ""
        }
        return names.contains { $0 != "." } ? .hasFiles : .empty
    }

    static func pull(_ result: ChildProcess.Result) -> PullOutcome {
        let statistics = statistics(in: result.standardOutput)
        switch result.status {
        case 0:
            return PullOutcome(failure: nil, vanishedFiles: false, statistics: statistics)
        case vanishedFilesStatus:
            return PullOutcome(failure: nil, vanishedFiles: true, statistics: statistics)
        default:
            return PullOutcome(failure: failure(in: result), vanishedFiles: false, statistics: statistics)
        }
    }

    private static func failure(in result: ChildProcess.Result) -> BackupFailure {
        // rsync passes on ssh's own failures with ssh's messages, and with ssh's status when it sees ssh
        // exit first. When it sees the connection close first, the status is its own protocol error.
        if [SSHFailureReader.sshErrorStatus, protocolStreamStatus].contains(result.status),
           let connection = SSHFailureReader.recognizedFailure(in: result.standardError) {
            return BackupFailure(connection)
        }
        let output = String(bytes: result.standardError, encoding: .utf8) ?? ""
        switch result.status {
        case partialTransferStatus:
            if output.contains("change_dir"), missingSourceMessages.contains(where: output.contains) { return .sourceMissing }
            if output.contains("change_dir"), output.contains(unreadableSourceMessage) { return .sourceUnreadable }
            return .someFilesNotTransferred
        case timeoutStatus:
            return .stalled
        case interruptedStatus:
            return .cancelled
        default:
            return .failed
        }
    }

    /// From `--stats`, which `--no-human-readable` leaves as plain numbers.
    static func statistics(in output: Data) -> PullStatistics {
        var statistics = PullStatistics()
        for line in (String(bytes: output, encoding: .utf8) ?? "").split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let digits = parts[1].drop { $0 == " " }.prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)
            guard let value = Int64(digits) else { continue }
            switch parts[0] {
            case "Number of regular files transferred": statistics.filesTransferred = Int(value)
            case "Total transferred file size": statistics.bytesTransferred = value
            case "Total bytes received": statistics.bytesReceived = value
            default: break
            }
        }
        return statistics
    }
}
