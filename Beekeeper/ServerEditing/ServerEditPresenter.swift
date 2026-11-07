import HiveKit
import SwiftUI

/// Editing or removing a server, asked for from its page or its row in the sidebar.
struct ServerEditRequest: Identifiable {
    enum Action {
        case edit
        case remove
    }

    let action: Action
    let server: Server
    let servers: ServerList

    var id: UUID {
        server.id
    }
}

/// Shows the edit sheet, or asks before removing, for whichever server a request names.
private struct ServerEditPresenter: ViewModifier {
    @Binding var request: ServerEditRequest?
    let onRemoved: (Server) -> Void

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: requested(.edit)) { request in
                EditServerSheet(servers: request.servers, server: request.server)
            }
            .confirmationDialog(
                "Remove “\(request?.server.name ?? "")”?",
                isPresented: isRequested(.remove),
                presenting: request
            ) { request in
                Button("Remove Server", role: .destructive) { Task { await remove(request) } }
            } message: { _ in
                Text("Its backup jobs are removed with it. Their snapshots stay on the backup drive.")
            }
            .alert("Couldn't Remove the Server", isPresented: isFailing) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func requested(_ action: ServerEditRequest.Action) -> Binding<ServerEditRequest?> {
        Binding {
            request?.action == action ? request : nil
        } set: { request = $0 }
    }

    private func isRequested(_ action: ServerEditRequest.Action) -> Binding<Bool> {
        Binding {
            request?.action == action
        } set: { isShown in
            if !isShown { request = nil }
        }
    }

    private var isFailing: Binding<Bool> {
        Binding { failure != nil } set: { if !$0 { failure = nil } }
    }

    private func remove(_ request: ServerEditRequest) async {
        do {
            try await request.servers.remove(request.server.id)
            onRemoved(request.server)
        } catch {
            failure = HiveLink.message(for: error)
        }
    }
}

extension View {
    func serverEditing(_ request: Binding<ServerEditRequest?>, onRemoved: @escaping (Server) -> Void) -> some View {
        modifier(ServerEditPresenter(request: request, onRemoved: onRemoved))
    }
}
