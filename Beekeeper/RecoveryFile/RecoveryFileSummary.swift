import HiveKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// On the Hive's overview: when the Hive last wrote its recovery file, and whether this device, and the
/// folder chosen on the Mac, have it.
struct RecoveryFileSummary: View {
    let copies: RecoveryFileCopies

    var body: some View {
        Section("Recovery File") {
            LabeledContent("Last written") {
                if let written = copies.hiveState?.fileWrittenAt {
                    // Each minute, and without seconds, so it never sits on a stale "47 seconds ago".
                    TimelineView(.everyMinute) { _ in
                        Text(written.formatted(Self.ago))
                    }
                    .help(written.formatted(date: .long, time: .shortened))
                } else {
                    Text("Not yet")
                }
            }
            LabeledContent(Self.thisDevice) {
                deviceCopy
            }
            #if os(macOS)
            if copies.folder != nil {
                LabeledContent("In “\(copies.folderName ?? "the chosen folder")”") {
                    folderCopy
                }
            }
            #endif
        }
    }

    @ViewBuilder private var deviceCopy: some View {
        if copies.hasLatest {
            HasLatestLabel()
        } else if copies.copyDigest != nil {
            IconAndText(text: "Has an older one", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        } else {
            Text("Doesn't have it yet")
                .foregroundStyle(.secondary)
        }
    }

    #if os(macOS)
    @ViewBuilder private var folderCopy: some View {
        if copies.folderProblem != nil {
            IconAndText(text: "Couldn't update it", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if copies.hasLatest {
            HasLatestLabel()
        } else {
            Text("Doesn't have it yet")
                .foregroundStyle(.secondary)
        }
    }
    #endif

    private static var thisDevice: String {
        #if os(macOS)
        "On this Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "On this iPad" : "On this iPhone"
        #endif
    }

    private static var ago: Date.RelativeFormatStyle {
        var style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        style.allowedFields = [.year, .month, .week, .day, .hour, .minute]
        return style
    }
}

private struct HasLatestLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Has the latest")
        }
    }
}

/// A `Label` as a form row's value leaves the row hundreds of points tall on iPad.
private struct IconAndText: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
    }
}
