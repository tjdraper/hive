import HiveKit
import SwiftUI

/// Adding a job to a server, or changing one, whole: what it backs up, when, and what it keeps. Lowering
/// what it keeps or replacing a database password asks for Touch ID or the password on Save.
struct JobEditorSheet: View {
    let jobs: JobList
    let serverID: UUID
    /// Nil to add a job.
    let job: BackupJob?
    var onSaved: ((BackupJob) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobEditorDraft
    @State private var problems = JobFieldProblems()
    @State private var isSaving = false
    @State private var failure: String?
    @State private var retentionEstimate: RemovalEstimate?

    init(jobs: JobList, serverID: UUID, job: BackupJob?, onSaved: ((BackupJob) -> Void)? = nil) {
        self.jobs = jobs
        self.serverID = serverID
        self.job = job
        self.onSaved = onSaved
        _draft = State(initialValue: job.map(JobEditorDraft.init) ?? JobEditorDraft())
    }

    var body: some View {
        SheetLayout(
            title: job == nil ? "Add a Job" : "Edit “\(job?.name ?? "")”",
            cancel: SheetButton(title: "Cancel") { dismiss() },
            confirm: SheetButton(title: job == nil ? "Add Job" : "Save", isDisabled: !draft.isComplete || isUnchanged || isSaving) {
                Task { await save() }
            },
            message: message
        ) {
            Form {
                Section {
                    StackedRow(title: "Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Example Site"))
                            .stackedField("Name")
                        FieldProblemText(problems[.name])
                    }
                }
                DirectoryFields(directories: $draft.directories, problems: problems)
                DatabaseFields(databases: $draft.databases, problems: problems)
                ScheduleFields(times: $draft.times, problems: problems)
                RetentionFields(retention: $draft.retention, saved: job?.retention, estimate: retentionEstimate, problems: problems)
            }
            .formStyle(.grouped)
        }
        .macSheetSize(width: 640, height: 680)
        // Hive's problems name rows by their place in the list it was sent, which adding or removing one changes.
        .onChange(of: draft.rowIDs) { problems = JobFieldProblems() }
        .task(id: draft.retention) { await estimateRetention() }
    }

    private var message: SheetMessage? {
        if let failure { return .problem(failure) }
        return problems.isEmpty ? nil : .problem("Hive turned some fields down. Each says why.")
    }

    /// Once the tiers stop changing.
    private func estimateRetention() async {
        retentionEstimate = nil
        guard let job, draft.retention.isLowered(from: job.retention) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        retentionEstimate = try? await jobs.estimate(tiers: draft.retention, of: job.id)
    }

    /// What Touch ID or the password prompt says, or nil when the change needs no confirming.
    private var confirmationReason: String? {
        guard let job else { return nil }
        var parts: [String] = []
        if draft.retention.isLowered(from: job.retention) {
            let deleting = switch retentionEstimate?.snapshotCount {
            case nil: ", which deletes snapshots"
            case 0: ""
            case .some(let count): ", deleting \(SnapshotCount(count))"
            }
            parts.append("lower what “\(job.name)” keeps\(deleting)")
        }
        if draft.databases.contains(where: { $0.hasSavedPassword && $0.newPassword != nil }) {
            parts.append("replace a database password of “\(job.name)”")
        }
        return parts.isEmpty ? nil : parts.formatted(.list(type: .and))
    }

    private var isUnchanged: Bool {
        guard let job else { return false }
        return draft.draft == job.draft
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = if let job {
                try await jobs.change(job.id, to: draft.draft, confirming: confirmationReason)
            } else {
                try await jobs.add(draft.draft, toServer: serverID)
            }
            onSaved?(saved)
            dismiss()
        } catch ConfirmationKeyError.cancelled {
            // Left as it was, to change or cancel.
        } catch {
            if let refused = JobFieldProblems(error) {
                problems = refused
                failure = nil
            } else {
                problems = JobFieldProblems()
                failure = HiveLink.message(for: error)
            }
        }
    }
}
