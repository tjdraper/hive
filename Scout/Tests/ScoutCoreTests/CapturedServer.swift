import ScoutCore

/// `/proc`, `/sys` and `/etc` files captured from real servers, one folder for each, laid out as on the server.
enum CapturedServer: String, CaseIterable {
    case debian12 = "debian-12"
    case ubuntu2404 = "ubuntu-24.04"
    case alpine322 = "alpine-3.22"
    case rocky9 = "rocky-9"

    private static let testsFolder = #filePath.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")

    var files: SystemFiles {
        SystemFiles(root: "\(Self.testsFolder)/Captured/\(rawValue)")
    }
}
