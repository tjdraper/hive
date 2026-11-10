import HiveKit
import SwiftUI

/// How many daily and monthly snapshots the job keeps.
struct RetentionFields: View {
    @Binding var retention: RetentionTiers
    /// The job's tiers as Hive has them, or nil for a new job.
    let saved: RetentionTiers?
    /// What lower tiers would delete, once Hive has worked it out.
    let estimate: RemovalEstimate?
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
            if retention.isLowered(from: saved) {
                Label {
                    switch estimate?.snapshotCount {
                    case nil:
                        Text("Lowering these deletes the snapshots they no longer keep, at Hive's next retention pass.")
                    case 0:
                        Text("These still keep every snapshot the job has, so none are deleted now. Saving asks you to confirm.")
                    case .some(let count):
                        Text(
                            "Lowering these deletes ^[\(count) snapshot](inflect: true) they no longer keep, at Hive's next retention pass."
                        )
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
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

extension RetentionTiers {
    /// Lower in either tier than `saved`. Hive asks for confirmation of that.
    func isLowered(from saved: RetentionTiers?) -> Bool {
        guard let saved else { return false }
        return dailySnapshots < saved.dailySnapshots || monthlySnapshots < saved.monthlySnapshots
    }
}
