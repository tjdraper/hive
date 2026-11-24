import HiveKit
import SwiftUI

/// A command to run on a server, for the kind of CPU chosen, since each gets its own Scout binary.
struct PlatformCommand: View {
    @Binding var platform: ScoutRelease.Platform
    let command: (ScoutRelease.Platform) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("CPU", selection: $platform) {
                ForEach(ScoutRelease.Platform.allCases, id: \.self) { platform in
                    Text(platform.label).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            Text("`uname -m` on the server prints which it has.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let text = command(platform) {
                CommandBox(text: text)
            } else {
                Label("Beekeeper couldn't make this command.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// A command set apart from the text around it, with a button to copy it.
struct CommandBox: View {
    let text: String

    var body: some View {
        CommandText(text: text)
            .padding(8)
            .background(.background.secondary, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

extension ScoutRelease.Platform {
    var label: String {
        switch self {
        case .x86: "x86_64 (Intel, AMD)"
        case .arm: "aarch64 (ARM)"
        }
    }
}
