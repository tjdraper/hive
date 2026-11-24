import HiveKit
import SwiftUI

/// Adds metrics to a server, or enrolls its Scout again, such as after a restore or a new identity. Where
/// Hive signs in to the server, it checks it first and installs or enrolls Scout itself when it can act as
/// root. Otherwise it opens an enrollment window and shows the command that installs Scout and enrolls
/// it, with the time left on its code, until the Scout enrolls or the code expires. Closing the sheet
/// closes the window.
struct AddMetricsSheet: View {
    let link: HiveLink
    let server: Server
    /// The Scout enrolled before the window opened, so a new one can be told from it.
    let previousEnrollment: Date?
    /// The CPU the last Scout reported, shown first.
    let reportedPlatform: String?
    let onEnrolled: () -> Void

    private enum Phase: Equatable {
        case checking
        /// Hive can install or enroll Scout over SSH itself.
        case overSSH(ScoutAction)
        case working(ScoutAction)
        case blocked(ScoutObstacle)
        case opening
        case open(EnrollmentWindow, expiresAt: Date)
        case enrolled(String?)
        case expired
        case failed(String)
    }

    private static let checkInterval = Duration.seconds(2)

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.opening
    @State private var platform = ScoutRelease.Platform.x86
    @State private var ssh: ScoutOverSSH?
    /// Why the command is shown rather than Hive installing Scout itself.
    @State private var why: String?
    /// Named in the command when Scout's rule would let Hive manage it from then on.
    @State private var sshUser: String?
    /// Why Hive's last try over SSH didn't work.
    @State private var actionFailure: String?

    var body: some View {
        SheetLayout(
            title: title,
            cancel: cancelButton,
            confirm: confirmButton,
            secondary: secondaryButton
        ) {
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                Text(title)
                    .font(.title2.bold())
                #endif
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macSheetSize(width: 640, height: 560)
        .interactiveDismissDisabled()
        .task { await start() }
        .task(id: openWindowID) { await watch() }
    }

    private var title: String {
        previousEnrollment == nil ? "Add Metrics to “\(server.name)”" : "Enroll Scout on “\(server.name)” Again"
    }

    private var cancelButton: SheetButton? {
        switch phase {
        case .enrolled, .blocked: nil
        case .working: SheetButton(title: "Cancel", isDisabled: true) {
            // Hive is already working on the server, which it finishes either way.
        }
        default: SheetButton(title: "Cancel") { close() }
        }
    }

    private var confirmButton: SheetButton? {
        switch phase {
        case .enrolled, .blocked: SheetButton(title: "Done") { close() }
        case .overSSH(let action): SheetButton(title: action == .install ? "Install" : "Enroll") { Task { await perform(action) } }
        default: nil
        }
    }

    private var secondaryButton: SheetButton? {
        switch phase {
        case .expired: SheetButton(title: "New Code") { Task { await open() } }
        case .overSSH: SheetButton(title: "Show Command Instead") { Task { await open() } }
        default: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .open(let window, let expiresAt):
            // Only the command can outgrow the sheet, such as on iPhone.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    openWindow(window, expiresAt: expiresAt)
                }
            }
        case .overSSH(let action):
            ScoutOverSSHOffer(action: action, server: server, found: ssh?.found, failure: actionFailure)
        default:
            // Fills the sheet below the title, so it sits in the middle of it.
            outcome
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var outcome: some View {
        switch phase {
        case .checking:
            ProgressView("Checking what Hive can do on “\(server.name)”…")
        case .working(let action):
            ProgressView(action == .install ? "Installing Scout on “\(server.name)”…" : "Enrolling Scout on “\(server.name)”…")
        case .opening:
            ProgressView("Opening an enrollment window…")
        case .enrolled(let message):
            ContentUnavailableView(
                "Scout Enrolled",
                systemImage: "checkmark.circle",
                description: Text(message ?? "Scout on “\(server.name)” is sending its figures to the Hive.")
            )
        case .blocked(let obstacle):
            ContentUnavailableView("Scout Can't Run Here", systemImage: "xmark.octagon", description: Text(obstacle.message))
        case .expired:
            ContentUnavailableView(
                "The Code Expired",
                systemImage: "clock.badge.xmark",
                description: Text("No Scout enrolled with it. Make a new code to try again.")
            )
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't Open an Enrollment Window",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .open, .overSSH:
            EmptyView()
        }
    }

    @ViewBuilder private func openWindow(_ window: EnrollmentWindow, expiresAt: Date) -> some View {
        if let why {
            Label(why, systemImage: "info.circle")
                .fixedSize(horizontal: false, vertical: true)
        }
        if let release = ThisBuildsScout.release {
            Text(
                "Run this as root on “\(server.name)”. It downloads Scout \(release.version), checks it, installs it as a service "
                    + "and enrolls it with this Hive. Running it again later updates Scout and keeps its enrollment."
            )
            .fixedSize(horizontal: false, vertical: true)
            PlatformCommand(platform: $platform) { ScoutCommand.install(release, for: $0, code: window.code, sshUser: sshUser) }
        } else {
            DevelopmentEnrollmentCode(code: window.code, sshUser: sshUser)
        }
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for Scout to enroll…")
                .foregroundStyle(.secondary)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Code expires in \(Self.remaining(until: expiresAt, now: context.date))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        Label(
            "Anyone with this code can send figures for “\(server.name)” until it's used or expires.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var openWindowID: UUID? {
        if case .open(let window, _) = phase { return window.id }
        return nil
    }

    /// Checks the server first where Hive signs in to it.
    private func start() async {
        platform = ThisBuildsScout.platform(reportedAs: reportedPlatform) ?? .x86
        let ssh = ScoutOverSSH(link: link, server: server)
        self.ssh = ssh
        guard ssh.canCheck else { return await open() }
        phase = .checking
        await ssh.refresh()
        switch ScoutInstallChoice(ssh: ssh, server: server) {
        case .overSSH(let action, let platform):
            self.platform = platform
            phase = .overSSH(action)
        case .blocked(let obstacle):
            phase = .blocked(obstacle)
        case .command(let why, let sshUser, let platform):
            if let platform { self.platform = platform }
            (self.why, self.sshUser) = (why, sshUser)
            await open()
        }
    }

    private func perform(_ action: ScoutAction) async {
        guard let ssh else { return }
        phase = .working(action)
        let done = await ssh.perform(action)
        if done {
            phase = .enrolled(ssh.outcome?.message)
            onEnrolled()
        } else {
            actionFailure = ssh.outcome?.message
            phase = .overSSH(action)
        }
    }

    private func open() async {
        phase = .opening
        do {
            let reason = "let a Scout send figures for “\(server.name)”"
            let path = HiveEndpoint.enrollmentWindow(forServer: server.id)
            let window: EnrollmentWindow = try await link.confirmed("POST", path, reason: reason)
            phase = .open(window, expiresAt: .now.addingTimeInterval(TimeInterval(window.expiresInSeconds)))
        } catch ConfirmationKeyError.cancelled {
            dismiss()
        } catch {
            phase = .failed(message(for: error))
        }
    }

    /// Until a new Scout enrolls or the code expires, or the sheet closes.
    private func watch() async {
        guard case .open(_, let expiresAt) = phase else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.checkInterval)
            guard !Task.isCancelled else { return }
            let state: ServerMetricsState? = try? await link.perform { try await $0.get(HiveEndpoint.metrics(ofServer: server.id)) }
            if let enrolledAt = state?.scout?.enrolledAt, enrolledAt != previousEnrollment {
                phase = .enrolled(nil)
                onEnrolled()
                return
            }
            if Date.now >= expiresAt {
                phase = .expired
                return
            }
        }
    }

    private func close() {
        if case .open = phase {
            let path = HiveEndpoint.enrollmentWindow(forServer: server.id)
            Task { try? await link.perform { try await $0.delete(path) } }
        }
        dismiss()
    }

    private static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func message(for error: any Error) -> String {
        if let refused = error as? HiveRequestError, refused.status == 422,
           (try? JSONDecoder().decode(EnrollmentWindowRefusal.self, from: refused.body))?.problem == .noAddressOptions {
            return "Add an address the server can reach the Hive at, under Addresses for Other Devices in Settings."
        }
        if let refused = error as? HiveRequestError, refused.status == 503 {
            return "The Hive is restarting. Try again in a moment."
        }
        return HiveLink.message(for: error)
    }
}
