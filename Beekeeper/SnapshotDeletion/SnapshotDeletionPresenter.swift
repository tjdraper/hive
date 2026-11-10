import HiveKit
import SwiftUI

/// Asks before deleting whichever snapshots a request names, then has Hive delete them once Touch ID
/// or the password confirms it.
private struct SnapshotDeletionPresenter: ViewModifier {
    @Binding var request: SnapshotDeletionRequest?
    let link: HiveLink
    let onRequested: (() -> Void)?

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(request?.title ?? "", isPresented: isRequested, presenting: request) { request in
                Button(request.buttonTitle, role: .destructive) { Task { await delete(request) } }
            } message: { request in
                Text(request.message)
            }
            .alert("Couldn't Delete", isPresented: isFailing) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private var isRequested: Binding<Bool> {
        Binding { request != nil } set: { if !$0 { request = nil } }
    }

    private var isFailing: Binding<Bool> {
        Binding { failure != nil } set: { if !$0 { failure = nil } }
    }

    private func delete(_ request: SnapshotDeletionRequest) async {
        do {
            try await link.confirmed("DELETE", request.path, reason: request.reason)
            onRequested?()
        } catch ConfirmationKeyError.cancelled {
            // Nothing deleted, as the person chose.
        } catch let refused as HiveRequestError where refused.status == 409 {
            failure = "A backup is writing to that snapshot now. Try again once it finishes."
        } catch let refused as HiveRequestError where refused.status == 404 {
            failure = "There's nothing left to delete."
            onRequested?()
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

extension View {
    /// `onRequested` runs once Hive has the request, to show the snapshots as being deleted.
    func snapshotDeletion(
        _ request: Binding<SnapshotDeletionRequest?>,
        link: HiveLink,
        onRequested: (() -> Void)? = nil
    ) -> some View {
        modifier(SnapshotDeletionPresenter(request: request, link: link, onRequested: onRequested))
    }
}
