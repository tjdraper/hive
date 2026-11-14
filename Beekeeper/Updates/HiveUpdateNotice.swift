import HiveKit
import SwiftUI

/// Hive and Beekeeper are released together, and Beekeeper on the Mac updates itself, so a Hive older
/// than this Beekeeper has an update waiting. Only Hive.app on the Hive's Mac can install it.
struct HiveUpdateNotice: View {
    static var beekeeperVersion: ReleaseVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(ReleaseVersion.init)
    }

    let hiveVersion: ReleaseVersion
    let beekeeperVersion: ReleaseVersion
    let isOnThisMac: Bool

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hive \(beekeeperVersion.description) is available")
                        .font(.headline)
                    Text(explanation)
                        .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            if isOnThisMac {
                OpenHiveButton()
            }
            #endif
        }
    }

    private var explanation: String {
        let running = "This Hive is running \(hiveVersion.description)."
        return isOnThisMac
            ? running + " Open Hive to update it. It asks for an administrator password."
            : running + " Open Hive on the Hive's Mac to update it."
    }
}

#if os(macOS)
struct OpenHiveButton: View {
    private let opener = HiveAppOpener()

    var body: some View {
        Button("Open Hive") { opener.open() }
            .disabled(opener.applicationURL == nil)
    }
}
#endif
