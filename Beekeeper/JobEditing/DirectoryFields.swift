import HiveKit
import SwiftUI

/// Each directory's path on the server and the folder it goes in within each snapshot.
struct DirectoryFields: View {
    @Binding var directories: [JobEditorDraft.Directory]
    let problems: JobFieldProblems

    var body: some View {
        Section {
            ForEach($directories) { $directory in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        StackedRow(title: "Path on the server") {
                            // Wraps, so a long path shows whole rather than scrolling inside its field.
                            TextField(
                                "Path on the server",
                                text: $directory.path,
                                prompt: Text("/var/www/example/uploads"),
                                axis: .vertical
                            )
                                .stackedField("Path on the server")
                                .onChange(of: directory.path) { old, new in
                                    // The folder follows the path until it's named something else.
                                    let suggested = JobEditorDraft.Directory.suggestedFolder(for: old)
                                    if directory.folder.isEmpty || directory.folder == suggested {
                                        directory.folder = JobEditorDraft.Directory.suggestedFolder(for: new)
                                    }
                                }
                        }
                        StackedRow(title: "Folder in each snapshot") {
                            TextField("Folder in each snapshot", text: $directory.folder, prompt: Text("uploads"), axis: .vertical)
                                .stackedField("Folder in each snapshot")
                        }
                        FieldProblemText(problems.messages(for: [.directoryPath, .directoryFolder], at: index(of: directory)))
                    }
                    .autocorrectionDisabled()
                    RemoveRowButton(label: "Remove Directory") { directories.removeAll { $0.id == directory.id } }
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
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: "minus.circle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(label)
    }
}
