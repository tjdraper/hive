import HiveKit
import SwiftUI

/// What the server is, as its Scout last said, and warnings about what makes its figures less than
/// they seem.
struct ServerFacts: View {
    let scout: ScoutState
    let history: ServerHistory?
    /// The server's clock, now.
    let serverNow: Int64

    /// Beekeeper warns past this (§5).
    private static let largestClockOffset = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { cells(0 ..< facts.count) }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow { cells(0 ..< 3) }
                    GridRow { cells(3 ..< 6) }
                }
            }
            warnings
        }
    }

    private var facts: [(String, String)] {
        [
            ("System", scout.distribution ?? "—"),
            ("Kernel", scout.kernel ?? "—"),
            ("Cores", history?.cores.map { String(Int($0.rounded())) } ?? "—"),
            ("Memory", history?.memoryTotal.map { Int64($0.rounded()).formatted(.byteCount(style: .memory)) } ?? "—"),
            ("Up", uptime ?? "—"),
            ("Scout", scout.version ?? "—"),
        ]
    }

    private func cells(_ range: Range<Int>) -> some View {
        ForEach(range, id: \.self) { index in
            VStack(alignment: .leading, spacing: 2) {
                Text(facts[index].0)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(facts[index].1)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var warnings: some View {
        if let offset = scout.clockOffsetSeconds, abs(offset) > Self.largestClockOffset {
            Label(
                "The server's clock is \(Self.clockDescription(offset)) the Hive's, so its figures show at the wrong times.",
                systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(.orange)
        }
        if scout.processesHidden == true {
            Label("The server hides other users' processes from Scout, so it reports none.", systemImage: "eye.slash")
                .foregroundStyle(.secondary)
        }
    }

    private var uptime: String? {
        guard let startedAt = scout.startedAt, serverNow > startedAt else { return nil }
        return Duration.seconds(serverNow - startedAt)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
    }

    private static func clockDescription(_ offset: Int) -> String {
        let amount = Duration.seconds(abs(offset)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return offset > 0 ? "\(amount) ahead of" : "\(amount) behind"
    }
}
