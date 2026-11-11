/// Which versions of the API a build speaks. `current` goes up whenever Hive or Beekeeper would
/// misread what the other sends, and `oldestCompatible` whenever this build stops understanding a
/// version of the other side.
public struct APIVersions: Codable, Hashable, Sendable {
    public static let thisBuild = APIVersions(current: 2, oldestCompatible: 2)

    public let current: Int
    public let oldestCompatible: Int

    public init(current: Int, oldestCompatible: Int) {
        self.current = current
        self.oldestCompatible = oldestCompatible
    }

    /// The app to update so the two can work together, or nil when they already can. At most one side
    /// can be too old, since each side's current version is at least its own oldest compatible one.
    public static func outdatedApp(hive: APIVersions, beekeeper: APIVersions) -> OutdatedApp? {
        if beekeeper.current < hive.oldestCompatible { return .beekeeper }
        if hive.current < beekeeper.oldestCompatible { return .hive }
        return nil
    }
}

public enum OutdatedApp: String, Codable, Sendable {
    case hive
    case beekeeper
}
