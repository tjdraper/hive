import ScoutCore

/// What `hive-scout status` prints from the running Scout's status.
enum StatusReport {
    /// A running Scout updates its status every 10 seconds.
    static let staleSeconds: Int64 = 30

    static func text(for status: SendingStatus?, now: Int64) -> String {
        guard let status else { return "Scout isn't running, or hasn't taken a sample yet." }
        var lines: [String] = []
        if now - status.updatedAt > staleSeconds {
            lines.append("Scout hasn't updated its status for \(duration(now - status.updatedAt)), so it may have stopped. As it last was:")
        }
        switch status.state {
        case .connecting: lines.append("Connecting to Hive.")
        case .sending: lines.append("Sending to Hive.")
        case .unreachable: lines.append(status.problem ?? "Can't reach Hive.")
        case .refused: lines.append("Refused by Hive. \(status.problem ?? "")")
        }
        if let delivered = status.lastDeliveredAt {
            lines.append("Last sent \(duration(max(0, now - delivered))) ago.")
        } else {
            lines.append("Nothing sent since Scout started.")
        }
        if let refusal = status.lastRefusal { lines.append("Hive refused the last samples it turned away: \(refusal).") }
        lines.append("Holding \(status.heldSamples) samples and \(status.heldMinutes) minutes.")
        return lines.joined(separator: "\n")
    }

    private static func duration(_ seconds: Int64) -> String {
        switch seconds {
        case ..<120: "\(seconds) seconds"
        case ..<7_200: "\(seconds / 60) minutes"
        default: "\(seconds / 3_600) hours"
        }
    }
}
