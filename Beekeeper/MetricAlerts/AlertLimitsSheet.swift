import HiveKit
import SwiftUI

/// When Hive emails about a server's figures, each limit beside its default, with a way back to them all.
struct AlertLimitsSheet: View {
    let link: HiveLink
    let server: Server
    let onSave: (MetricAlertLimits) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saved: MetricAlertLimits?
    @State private var draft = MetricAlertLimits.defaults
    @State private var loadFailure: String?
    @State private var saveFailure: String?
    @State private var isSaving = false

    var body: some View {
        SheetLayout(
            title: "Alert Limits for “\(server.name)”",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(title: "Save", isDisabled: saved == nil || draft == saved || !draft.isValid || isSaving) {
                Task { await save() }
            },
            secondary: SheetButton(title: "Use Defaults", isDisabled: saved == nil || draft == .defaults) { draft = .defaults },
            message: message
        ) {
            if saved != nil {
                fields
            } else if let loadFailure {
                ContentUnavailableView {
                    Label("Couldn't Read Alert Limits", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadFailure)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .macSheetSize(width: 520, height: 780)
        .task { await load() }
    }

    private var message: SheetMessage? {
        if isSaving { return .working(nil) }
        return saveFailure.map(SheetMessage.problem)
    }

    private var fields: some View {
        Form {
            Section {
                limit("Used over", \.filesystemUsedPercent, in: MetricAlertLimits.percentRange, unit: .percent)
                limit("Forecast to fill within", \.filesystemFillDays, in: MetricAlertLimits.fillDaysRange, unit: .days)
            } header: {
                Text("Disks")
            } footer: {
                Text("Each filesystem, for its space and its inodes. The forecast is from how fast it filled over the last week.")
                    .foregroundStyle(.secondary)
            }
            Section {
                limit("Available under", \.memoryAvailablePercent, in: MetricAlertLimits.percentRange, unit: .percent)
                limit("For", \.memoryMinutes, in: MetricAlertLimits.minutesRange, unit: .minutes)
            } header: {
                Text("Memory")
            } footer: {
                Text("Swapping in steadily, over 50 pages a second, counts as short too. It ends after an hour within the limits.")
                    .foregroundStyle(.secondary)
            }
            Section {
                limit("Busy over", \.cpuBusyPercent, in: MetricAlertLimits.percentRange, unit: .percent)
                limit("Steal over", \.cpuStealPercent, in: MetricAlertLimits.percentRange, unit: .percent)
                limit("Load over", \.loadPerCore, in: MetricAlertLimits.loadPerCoreRange, step: 0.5, unit: .perCore)
                limit("For", \.cpuMinutes, in: MetricAlertLimits.minutesRange, unit: .minutes)
            } header: {
                Text("CPU")
            } footer: {
                Text("""
                Any one of these counts. Busy is user, system, I/O wait and steal together, as the dashboard shows it, and \
                steal is time the host gave to others. It ends after an hour within the limits.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private enum Unit: String {
        case percent = "%"
        case days
        case minutes
        case perCore = "per core"

        /// The defaults are never 1, so no unit needs a singular.
        func describe(_ number: String) -> String {
            self == .percent ? "\(number)%" : "\(number) \(rawValue)"
        }
    }

    private func limit(
        _ title: String,
        _ figure: WritableKeyPath<MetricAlertLimits, Int>,
        in range: ClosedRange<Int>,
        unit: Unit
    ) -> some View {
        let value = $draft[dynamicMember: figure]
        return row(
            title,
            defaultValue: String(MetricAlertLimits.defaults[keyPath: figure]),
            unit: unit,
            problem: range.contains(value.wrappedValue) ? nil : "From \(range.lowerBound) to \(range.upperBound)."
        ) {
            TextField(title, value: value, format: .number.grouping(.never))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Stepper(title, value: value, in: range)
        }
    }

    private func limit(
        _ title: String,
        _ figure: WritableKeyPath<MetricAlertLimits, Double>,
        in range: ClosedRange<Double>,
        step: Double,
        unit: Unit
    ) -> some View {
        let value = $draft[dynamicMember: figure]
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 2))
        return row(
            title,
            defaultValue: MetricAlertLimits.defaults[keyPath: figure].formatted(format),
            unit: unit,
            problem: range.contains(value.wrappedValue)
                ? nil
                : "From \(range.lowerBound.formatted(format)) to \(range.upperBound.formatted(format))."
        ) {
            TextField(title, value: value, format: format)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Stepper(title, value: value, in: range, step: step)
        }
    }

    /// The field and its stepper, with the default under the title.
    private func row(
        _ title: String,
        defaultValue: String,
        unit: Unit,
        problem: String?,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    controls()
                        .labelsHidden()
                    Text(unit.rawValue)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
                FieldProblemText(problem)
            }
        } label: {
            Text(title)
            Text("Default \(unit.describe(defaultValue))")
        }
    }

    private func load() async {
        loadFailure = nil
        do {
            let limits: MetricAlertLimits = try await link.perform { try await $0.get(HiveEndpoint.metricAlertLimits(ofServer: server.id)) }
            saved = limits
            draft = limits
        } catch is CancellationError {
            return
        } catch {
            loadFailure = HiveLink.message(for: error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let limits: MetricAlertLimits = try await link.perform {
                try await $0.put(HiveEndpoint.metricAlertLimits(ofServer: server.id), body: draft)
            }
            onSave(limits)
            dismiss()
        } catch {
            saveFailure = HiveLink.message(for: error)
        }
    }
}
