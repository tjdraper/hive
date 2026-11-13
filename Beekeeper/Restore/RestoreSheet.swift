import HiveKit
import SwiftUI
import UniformTypeIdentifiers

/// Restoring a new Hive on this Mac from one of its recovery files and its recovery key (§14). Hive
/// takes back the old Hive's ID, servers, jobs, passwords and SSH keys, then restarts as that Hive.
struct RestoreSheet: View {
    let hive: KnownHive
    let link: HiveLink
    let onRestored: (RestoreOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(HiveListStore.self) private var store
    @State private var draft = RestoreDraft()
    @State private var stored: [StoredRecoveryFile] = []
    @State private var isChoosingFile = false
    @State private var fileProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Restore from a Recovery File")
                            .font(.title2.bold())
                        Text(
                            "Brings back a Hive whose Mac was lost or replaced, with its servers, jobs, passwords and SSH keys. "
                                + "This Mac's Hive takes its place, and every other device pairs with it again."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                fileSection
                keySection
                if let failure = draft.failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if draft.isRestoring {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(draft.isRestoring)
                Button("Restore") { Task { await restore() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete || draft.isRestoring)
            }
            .padding()
        }
        .macSheetSize(width: 560, height: 520)
        .interactiveDismissDisabled(draft.isRestoring)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [Self.recoveryFileType]) { result in
            guard case .success(let url) = result else { return }
            choose(url)
        }
        .fileDialogMessage("Choose a recovery file, such as one in iCloud Drive or in a Mac backup of the Hive's old Mac.")
        .fileDialogConfirmationLabel("Choose")
        .task { stored = await StoredRecoveryFile.all() }
    }

    private var fileSection: some View {
        Section {
            ForEach(stored) { file in
                Button { choose(file.url) } label: {
                    HStack {
                        Image(systemName: draft.file?.url == file.url ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(name(of: file))
                            Text("Kept by Beekeeper, \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            HStack {
                if let file = draft.file, !stored.contains(where: { $0.url == file.url }) {
                    Label(file.url.lastPathComponent, systemImage: "doc")
                } else if stored.isEmpty {
                    Text("No file chosen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose File…") { isChoosingFile = true }
            }
            if let fileProblem {
                Label(fileProblem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Recovery File")
        } footer: {
            Text(
                "Every device paired with the Hive keeps its latest recovery file, and so does the Hive's own data folder, "
                    + "which the Mac's backup picks up."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var keySection: some View {
        Section {
            StackedRow(title: "Recovery Key") {
                TextField("Recovery Key", text: $draft.code, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .stackedField("Recovery Key")
            }
            if let problem = draft.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("The key saved in your password manager when the Hive was set up. Hive uses it to open the file, and doesn't keep it.")
                .foregroundStyle(.secondary)
        }
    }

    private static var recoveryFileType: UTType {
        UTType(filenameExtension: RecoveryFileHeader.fileExtension) ?? .data
    }

    private func name(of file: StoredRecoveryFile) -> String {
        if let id = file.hiveID, let known = store.hive(id) {
            return "“\(known.name)”"
        }
        return "A Hive this Mac knew before"
    }

    private func choose(_ url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            draft.file = RestoreDraft.ChosenFile(url: url, data: try Data(contentsOf: url))
            fileProblem = nil
        } catch {
            fileProblem = "Beekeeper couldn't read that file."
        }
    }

    private func restore() async {
        guard let outcome = await draft.restore(on: link) else { return }
        onRestored(outcome)
        dismiss()
    }
}
