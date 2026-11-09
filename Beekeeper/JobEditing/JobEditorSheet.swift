import HiveKit
import SwiftUI

/// Adding a job to a server, or changing one, whole: what it backs up, when, and what it keeps.
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

    init(jobs: JobList, serverID: UUID, job: BackupJob?, onSaved: ((BackupJob) -> Void)? = nil) {
        self.jobs = jobs
        self.serverID = serverID
        self.job = job
        self.onSaved = onSaved
        _draft = State(initialValue: job.map(JobEditorDraft.init) ?? JobEditorDraft())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Name") {
                        VStack(alignment: .trailing, spacing: 4) {
                            TextField("Name", text: $draft.name, prompt: Text("Example Site"))
                                .labelsHidden()
                            FieldProblemText(problems[.name])
                        }
                    }
                }
                DirectoryFields(directories: $draft.directories, problems: problems)
                DatabaseFields(databases: $draft.databases, problems: problems)
                ScheduleFields(times: $draft.times, problems: problems)
                RetentionFields(retention: $draft.retention, saved: job?.retention, problems: problems)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                } else if !problems.isEmpty {
                    Label("Hive turned some fields down. Each says why.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(job == nil ? "Add Job" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete || isUnchanged || isSaving)
            }
            .padding()
        }
        .frame(width: 640, height: 680)
        // Hive's problems name rows by their place in the list it was sent, which adding or removing one changes.
        .onChange(of: draft.rowIDs) { problems = JobFieldProblems() }
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
                try await jobs.change(job.id, to: draft.draft)
            } else {
                try await jobs.add(draft.draft, toServer: serverID)
            }
            onSaved?(saved)
            dismiss()
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
