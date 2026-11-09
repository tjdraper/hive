import HiveKit
import SwiftUI

/// Editing or removing a job, asked for from its page or its row in the sidebar.
struct JobEditRequest: Identifiable {
    enum Action {
        case edit
        case remove
    }

    let action: Action
    let job: BackupJob
    let jobs: JobList

    var id: UUID {
        job.id
    }
}

/// Shows the job editor, or asks before removing, for whichever job a request names.
private struct JobEditPresenter: ViewModifier {
    @Binding var request: JobEditRequest?
    let onRemoved: (BackupJob) -> Void

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: requested(.edit)) { request in
                JobEditorSheet(jobs: request.jobs, serverID: request.job.serverID, job: request.job)
            }
            .confirmationDialog(
                "Remove “\(request?.job.name ?? "")”?",
                isPresented: isRequested(.remove),
                presenting: request
            ) { request in
                Button("Remove Job", role: .destructive) { Task { await remove(request) } }
            } message: { _ in
                Text("Hive stops backing it up. Its snapshots stay on the backup drive.")
            }
            .alert("Couldn't Remove the Job", isPresented: isFailing) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func requested(_ action: JobEditRequest.Action) -> Binding<JobEditRequest?> {
        Binding {
            request?.action == action ? request : nil
        } set: { request = $0 }
    }

    private func isRequested(_ action: JobEditRequest.Action) -> Binding<Bool> {
        Binding {
            request?.action == action
        } set: { isShown in
            if !isShown { request = nil }
        }
    }

    private var isFailing: Binding<Bool> {
        Binding { failure != nil } set: { if !$0 { failure = nil } }
    }

    private func remove(_ request: JobEditRequest) async {
        do {
            try await request.jobs.remove(request.job.id)
            onRemoved(request.job)
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

extension View {
    func jobEditing(_ request: Binding<JobEditRequest?>, onRemoved: @escaping (BackupJob) -> Void) -> some View {
        modifier(JobEditPresenter(request: request, onRemoved: onRemoved))
    }
}
