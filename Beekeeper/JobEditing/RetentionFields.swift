import HiveKit
import SwiftUI

/// How many daily and monthly snapshots the job keeps.
struct RetentionFields: View {
    @Binding var retention: RetentionTiers
    /// The job's tiers as Hive has them, or nil for a new job.
    let saved: RetentionTiers?
    let problems: JobFieldProblems

    var body: some View {
        Section {
            tier("Daily snapshots", value: $retention.dailySnapshots, range: 1 ... 3650, problem: problems[.dailySnapshots]) {
                Text("The newest from each of the last ^[\(retention.dailySnapshots) day](inflect: true) with a snapshot.")
            }
            tier("Monthly snapshots", value: $retention.monthlySnapshots, range: 0 ... 1200, problem: problems[.monthlySnapshots]) {
                if retention.monthlySnapshots == 0 {
                    Text("None beyond the daily ones.")
                } else {
                    Text("The newest from each of the last ^[\(retention.monthlySnapshots) month](inflect: true) with a snapshot.")
                }
            }
            if let saved, retention.dailySnapshots < saved.dailySnapshots || retention.monthlySnapshots < saved.monthlySnapshots {
                Label(
                    "Lowering these deletes the snapshots they no longer keep, at Hive's next retention pass.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Keeps")
        } footer: {
            Text("Days and months without a snapshot aren't counted, so a long outage never ages out older snapshots.")
                .foregroundStyle(.secondary)
        }
    }

    private func tier(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        problem: String?,
        @ViewBuilder note: () -> some View
    ) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    TextField(title, value: value, format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Stepper(title, value: value, in: range)
                        .labelsHidden()
                }
                note()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FieldProblemText(problem)
            }
        }
    }
}
