import Foundation

extension URL {
    /// The path without the trailing slash a folder's URL carries. lstat and open follow a symbolic
    /// link named with a trailing slash, which would defeat the checks that refuse links.
    var fileSystemPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
