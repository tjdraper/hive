import HiveKit
import SwiftUI

/// The most space a server's snapshots may take, or none, beside what they take now.
struct QuotaField: View {
    enum Unit: Int64, CaseIterable, Identifiable {
        case gigabytes = 1_000_000_000
        case terabytes = 1_000_000_000_000

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .gigabytes: "GB"
            case .terabytes: "TB"
            }
        }
    }

    /// A new quota starts at this or above, so turning one on doesn't start removing snapshots straight away.
    private static let smallestSuggested: Int64 = 100_000_000_000

    @Binding var quotaBytes: Int64?
    let saved: Int64?
    let space: ServerSpace?
    /// What a lower quota would delete, once Hive has worked it out.
    let estimate: RemovalEstimate?
    let problem: String?

    @State private var amount: Double
    @State private var unit: Unit

    init(quotaBytes: Binding<Int64?>, saved: Int64?, space: ServerSpace?, estimate: RemovalEstimate?, problem: String?) {
        _quotaBytes = quotaBytes
        self.saved = saved
        self.space = space
        self.estimate = estimate
        self.problem = problem
        let bytes = quotaBytes.wrappedValue ?? Self.smallestSuggested
        let unit: Unit = bytes >= Unit.terabytes.rawValue && bytes % Unit.terabytes.rawValue == 0 ? .terabytes : .gigabytes
        _unit = State(initialValue: unit)
        _amount = State(initialValue: Double(bytes) / Double(unit.rawValue))
    }

    var body: some View {
        Section {
            Toggle("Limit the space its snapshots take", isOn: hasQuota)
            if quotaBytes != nil {
                LabeledContent("Quota") {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            TextField("Quota", value: $amount, format: .number.precision(.fractionLength(0 ... 2)))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Picker("Unit", selection: $unit) {
                                ForEach(Unit.allCases) { Text($0.title).tag($0) }
                            }
                            .fixedSize()
                        }
                        .labelsHidden()
                        FieldProblemText(problem)
                    }
                }
            }
            LabeledContent("Uses now", value: ServerSpace.describe(space))
            if Self.isLowered(from: saved, to: quotaBytes) {
                Label {
                    switch estimate?.snapshotCount {
                    case nil:
                        Text("A lower quota deletes this server's oldest daily snapshots until it fits, at Hive's next retention pass.")
                    case 0:
                        Text("Its snapshots fit the lower quota, so none are deleted now. Saving asks you to confirm.")
                    case .some(let count):
                        // One literal, which `Text` localizes and inflects. Joining two with `+` makes a plain `String`.
                        Text("""
                        A lower quota deletes up to ^[\(count) snapshot](inflect: true), the server's oldest daily ones, \
                        at Hive's next retention pass.
                        """)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Space")
        } footer: {
            Text(
                "Covers all of the server's jobs on the backup drive, counting a file shared between snapshots once. "
                    + "Hive never removes a monthly snapshot or a job's newest to meet it."
            )
            .foregroundStyle(.secondary)
        }
        .onChange(of: amount) { applyAmount() }
        .onChange(of: unit) { applyAmount() }
    }

    private var hasQuota: Binding<Bool> {
        Binding {
            quotaBytes != nil
        } set: { isOn in
            if isOn {
                let suggested = suggestedBytes
                unit = suggested % Unit.terabytes.rawValue == 0 ? .terabytes : .gigabytes
                amount = Double(suggested) / Double(unit.rawValue)
                quotaBytes = suggested
            } else {
                quotaBytes = nil
            }
        }
    }

    /// The saved quota, or twice what the server uses now in whole hundreds of gigabytes.
    private var suggestedBytes: Int64 {
        if let saved { return saved }
        let hundred = Self.smallestSuggested
        let doubled = (space?.usedBytes ?? 0) * 2
        return max(hundred, (doubled + hundred - 1) / hundred * hundred)
    }

    /// No quota is the highest. Hive asks for confirmation of any lower one.
    static func isLowered(from saved: Int64?, to new: Int64?) -> Bool {
        switch (saved, new) {
        case (nil, .some): true
        case (.some(let saved), .some(let new)): new < saved
        case (_, nil): false
        }
    }

    private func applyAmount() {
        guard quotaBytes != nil else { return }
        quotaBytes = Int64((amount * Double(unit.rawValue)).rounded())
    }
}

extension ServerSpace {
    /// What the server's snapshots take, for showing beside its quota.
    static func describe(_ space: ServerSpace?) -> String {
        guard let space else { return "…" }
        guard let used = space.usedBytes else { return "Not counted yet" }
        return used.formatted(.byteCount(style: .file))
    }
}
