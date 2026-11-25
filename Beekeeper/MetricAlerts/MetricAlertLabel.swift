import HiveKit
import SwiftUI

/// One of a server's open alerts, as a sentence with an icon, for its pages.
struct MetricAlertLabel: View {
    let alert: MetricAlert

    var body: some View {
        Label {
            Text(sentence)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        // As the reporting badge colors these states.
        .foregroundStyle(alert.isStoppedReporting ? .red : .orange)
    }

    private var symbol: String {
        switch alert {
        case .stoppedReporting: "exclamationmark.octagon.fill"
        case .clockAhead: "clock.badge.exclamationmark"
        case .filesystemFilling, .memoryShort, .cpuBusy: "exclamationmark.triangle.fill"
        }
    }

    private var sentence: String {
        switch alert {
        case .stoppedReporting(let since, let withOthers):
            "Stopped reporting. Its last report was \(since.formatted(.relative(presentation: .named)))."
                + (withOthers ? " Other servers stopped at the same time, so the Hive's own connection is the likelier cause." : "")
        case .clockAhead:
            "Its clock is so far ahead of the Hive's that the Hive refuses its figures."
        case .filesystemFilling(let mountPoint):
            "“\(mountPoint)” is past its limit for space or inodes used, or forecast to fill soon."
        case .memoryShort:
            "Short of memory: little is available, or it's swapping in steadily."
        case .cpuBusy:
            "CPU busy: its use, steal or load has been past its limit."
        }
    }
}

extension MetricAlert {
    /// A few words for a dashboard card.
    var title: String {
        switch self {
        case .stoppedReporting: "Stopped reporting"
        case .clockAhead: "Clock ahead"
        case .filesystemFilling(let mountPoint): "“\(mountPoint)” filling up"
        case .memoryShort: "Short of memory"
        case .cpuBusy: "CPU busy"
        }
    }

    /// Whether it's about the server's figures, rather than whether they arrive.
    var isAboutFigures: Bool {
        switch self {
        case .stoppedReporting, .clockAhead: false
        case .filesystemFilling, .memoryShort, .cpuBusy: true
        }
    }

    /// CPU, memory, then disks, as the dashboard and charts order them.
    var figureOrder: Int {
        switch self {
        case .stoppedReporting, .clockAhead: 0
        case .cpuBusy: 1
        case .memoryShort: 2
        case .filesystemFilling: 3
        }
    }

    var isStoppedReporting: Bool {
        if case .stoppedReporting = self { true } else { false }
    }
}
