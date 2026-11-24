import HiveKit
import SwiftUI

/// What Hive will do when it installs or enrolls Scout over SSH itself.
struct ScoutOverSSHOffer: View {
    let action: ScoutAction
    let server: Server
    let found: ScoutServerCheck?
    /// Why the last try didn't work.
    let failure: String?

    var body: some View {
        let user = found?.sshUser ?? "its SSH user"
        Group {
            if action == .install {
                Text(
                    "Hive signs in to “\(server.name)” as \(user), which can run commands as root, so Hive can install Scout "
                        + "itself. It copies the Scout this Hive carries to the server, checks it, installs it as a service and "
                        + "enrolls it with this Hive. Later, Beekeeper can update and uninstall it the same way."
                )
            } else {
                Text(
                    "Scout \(found?.installedVersion ?? "") is installed on “\(server.name)”, and Hive can enroll it again "
                        + "itself, with a new key. The figures it holds are kept and sent once it's enrolled."
                )
            }
            Text("Whoever enrolls can send figures for “\(server.name)”, so this asks for confirmation.")
                .foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Only a release knows where Scout is downloaded from, so a development build shows the code for
/// `Scripts/scout-test-vm.sh install`, which copies the development binary in instead.
struct DevelopmentEnrollmentCode: View {
    let code: String
    let sshUser: String?

    var body: some View {
        let option = sshUser.map { " --ssh-user \($0)" } ?? ""
        Text(
            "This build of Beekeeper has no address to download Scout from, which only a release has. "
                + "Pass this code to Scripts/scout-test-vm.sh install\(option) on its standard input."
        )
        .fixedSize(horizontal: false, vertical: true)
        if ScoutCommand.isCode(code) {
            CommandBox(text: code)
        } else {
            Label("The Hive sent something that isn't an enrollment code.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
