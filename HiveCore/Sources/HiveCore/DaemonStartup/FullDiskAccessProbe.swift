import Darwin

public enum FullDiskAccess: String, Sendable {
    case granted
    case missing
    case unknown
}

/// A daemon can't ask for Full Disk Access, so it finds out by trying to read a file the permission guards.
public struct FullDiskAccessProbe {
    /// Readable by everyone as far as file permissions go, so only Full Disk Access decides whether opening it works.
    static let protectedFile = "/Library/Application Support/com.apple.TCC/TCC.db"

    /// Returns 0 when the file opened, or the error number.
    let tryOpening: (String) -> Int32

    public init() {
        self.init { path in
            let descriptor = open(path, O_RDONLY | O_CLOEXEC)
            guard descriptor != -1 else { return errno }
            close(descriptor)
            return 0
        }
    }

    init(tryOpening: @escaping (String) -> Int32) {
        self.tryOpening = tryOpening
    }

    public func check() -> FullDiskAccess {
        switch tryOpening(Self.protectedFile) {
        case 0: .granted
        case EPERM, EACCES: .missing
        default: .unknown
        }
    }
}
