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
    let problem: String?

    @State private var amount: Double
    @State private var unit: Unit

    init(quotaBytes: Binding<Int64?>, saved: Int64?, space: ServerSpace?, problem: String?) {
        _quotaBytes = quotaBytes
        self.saved = saved
        self.space = space
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
            if isLowered {
                Label(
                    "A lower quota deletes this server's oldest daily snapshots until it fits, at Hive's next retention pass.",
                    systemImage: "exclamationmark.triangle.fill"
                )
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

    private var isLowered: Bool {
        switch (saved, quotaBytes) {
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
