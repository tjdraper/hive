import AppKit
import ServiceManagement

@MainActor
struct SystemSettingsNavigator {
    private static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openFullDiskAccess() {
        guard let url = Self.fullDiskAccessURL else { return }
        NSWorkspace.shared.open(url)
    }
}
