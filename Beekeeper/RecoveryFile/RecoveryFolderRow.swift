#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Choosing a folder on the Mac to keep another copy of the Hive's recovery file in, such as one in
/// iCloud Drive.
struct RecoveryFolderRow: View {
    let hiveName: String
    let copies: RecoveryFileCopies

    @State private var isChoosing = false

    var body: some View {
        LabeledContent("Also keep a copy in") {
            HStack(spacing: 12) {
                Text(copies.folder == nil ? "No folder" : copies.folderName ?? "…")
                    .foregroundStyle(.secondary)
                if copies.folder != nil {
                    Button("Stop") { Task { await copies.stopUsingFolder() } }
                        .help("Deletes the copy in this folder and keeps none there from now on.")
                }
                Button(copies.folder == nil ? "Choose…" : "Change…") { isChoosing = true }
            }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await copies.chooseFolder(url) }
        }
        .fileDialogMessage("Choose a folder for a copy of “\(hiveName)”'s recovery file, such as one in iCloud Drive.")
        .fileDialogConfirmationLabel("Choose")
        if let problem = copies.folderProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
#endif
