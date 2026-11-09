import HiveKit
import SwiftUI

/// Each directory's path on the server and the folder it goes in within each snapshot.
struct DirectoryFields: View {
    @Binding var directories: [JobEditorDraft.Directory]
    let problems: JobFieldProblems

    var body: some View {
        Section {
            if !directories.isEmpty {
                HStack {
                    Text("Path on the server")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Folder in each snapshot")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RemoveRowButton.placeholder
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ForEach($directories) { $directory in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Path on the server", text: $directory.path, prompt: Text("/var/www/example/uploads"))
                            .onChange(of: directory.path) { old, new in
                                // The folder follows the path until it's named something else.
                                let suggested = JobEditorDraft.Directory.suggestedFolder(for: old)
                                if directory.folder.isEmpty || directory.folder == suggested {
                                    directory.folder = JobEditorDraft.Directory.suggestedFolder(for: new)
                                }
                            }
                        TextField("Folder in each snapshot", text: $directory.folder, prompt: Text("uploads"))
                        RemoveRowButton(label: "Remove Directory") { directories.removeAll { $0.id == directory.id } }
                    }
                    .labelsHidden()
                    .autocorrectionDisabled()
                    FieldProblemText(problems.messages(for: [.directoryPath, .directoryFolder], at: index(of: directory)))
                }
            }
            Button("Add Directory", systemImage: "plus") { directories.append(JobEditorDraft.Directory()) }
            FieldProblemText(problems[.directories])
        } header: {
            Text("Directories")
        } footer: {
            Text("Folders can be nested with “/”, such as images/galleries.")
                .foregroundStyle(.secondary)
        }
    }

    /// Its place in the list sent, which Hive's problems refer to.
    private func index(of directory: JobEditorDraft.Directory) -> Int? {
        directories.firstIndex { $0.id == directory.id }
    }
}

/// The minus button at the end of a row in one of the editor's lists.
struct RemoveRowButton: View {
    /// Takes the button's space in a header row, so the columns above line up with the fields.
    static var placeholder: some View {
        Image(systemName: "minus.circle").hidden()
    }

    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: "minus.circle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(label)
    }
}
