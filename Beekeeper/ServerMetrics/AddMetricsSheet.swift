import HiveKit
import SwiftUI

/// Opens an enrollment window for the server and shows the command that installs Scout and enrolls it,
/// with the time left on its code, until the Scout enrolls or the code expires. Closing the sheet closes
/// the window. Also used to enroll a Scout again, such as after a restore or a new identity.
struct AddMetricsSheet: View {
    let link: HiveLink
    let server: Server
    /// The Scout enrolled before the window opened, so a new one can be told from it.
    let previousEnrollment: Date?
    /// The CPU the last Scout reported, shown first.
    let reportedPlatform: String?
    let onEnrolled: () -> Void

    private enum Phase: Equatable {
        case opening
        case open(EnrollmentWindow, expiresAt: Date)
        case enrolled
        case expired
        case failed(String)
    }

    private static let checkInterval = Duration.seconds(2)

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.opening
    @State private var platform = ScoutRelease.Platform.x86

    var body: some View {
        SheetLayout(
            title: title,
            cancel: isFinished ? nil : SheetButton(title: "Cancel") { close() },
            confirm: isFinished ? SheetButton(title: "Done") { close() } : nil,
            secondary: phase == .expired ? SheetButton(title: "New Code") { Task { await open() } } : nil
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
        .task {
            platform = ThisBuildsScout.platform(reportedAs: reportedPlatform) ?? .x86
            await open()
        }
        .task(id: openWindowID) { await watch() }
    }

    private var title: String {
        "Add Metrics to “\(server.name)”"
    }

    @ViewBuilder private var content: some View {
        if case .open(let window, let expiresAt) = phase {
            // Only the command can outgrow the sheet, such as on iPhone.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    openWindow(window, expiresAt: expiresAt)
                }
            }
        } else {
            // Fills the sheet below the title, so it sits in the middle of it.
            outcome
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var outcome: some View {
        switch phase {
        case .opening:
            ProgressView("Opening an enrollment window…")
        case .enrolled:
            ContentUnavailableView(
                "Scout Enrolled",
                systemImage: "checkmark.circle",
                description: Text("Scout on “\(server.name)” is sending its figures to the Hive.")
            )
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
        case .open:
            EmptyView()
        }
    }

    @ViewBuilder private func openWindow(_ window: EnrollmentWindow, expiresAt: Date) -> some View {
        if let release = ThisBuildsScout.release {
            Text(
                "Run this as root on “\(server.name)”. It downloads Scout \(release.version), checks it, installs it as a service "
                    + "and enrolls it with this Hive. Running it again later updates Scout and keeps its enrollment."
            )
            .fixedSize(horizontal: false, vertical: true)
            PlatformCommand(platform: $platform) { ScoutCommand.install(release, for: $0, code: window.code) }
        } else {
            developmentCode(window)
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

    /// Only a release knows where Scout is downloaded from, so a development build shows the code for
    /// `Scripts/scout-test-vm.sh install`, which copies the development binary in instead.
    @ViewBuilder private func developmentCode(_ window: EnrollmentWindow) -> some View {
        Text(
            "This build of Beekeeper has no address to download Scout from, which only a release has. "
                + "Pass this code to Scripts/scout-test-vm.sh install on its standard input."
        )
        .fixedSize(horizontal: false, vertical: true)
        if ScoutCommand.isCode(window.code) {
            CommandBox(text: window.code)
        } else {
            Label("The Hive sent something that isn't an enrollment code.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var isFinished: Bool {
        phase == .enrolled
    }

    private var openWindowID: UUID? {
        if case .open(let window, _) = phase { return window.id }
        return nil
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
                phase = .enrolled
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
