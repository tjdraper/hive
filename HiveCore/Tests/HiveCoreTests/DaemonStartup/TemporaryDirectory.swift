import Darwin
import Foundation

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "HiveCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ component: String) -> String {
        url.appending(path: component).path(percentEncoded: false)
    }
}

func permissions(of path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// A stand-in for Hive.app, owned by whoever runs the tests and writable only by them.
func makeBundle(in temporary: TemporaryDirectory) throws -> URL {
    let bundle = temporary.url.appending(path: "Hive.app", directoryHint: .isDirectory)
    let macOS = bundle.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    try Data("daemon".utf8).write(to: macOS.appending(path: "HiveDaemon"))
    for path in ["Hive.app", "Hive.app/Contents", "Hive.app/Contents/MacOS"] {
        chmod(temporary.path(path), 0o755)
    }
    chmod(temporary.path("Hive.app/Contents/MacOS/HiveDaemon"), 0o755)
    return bundle
}
