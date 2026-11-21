/// The routes Scout uses on Hive. Enrolling and signing in share the routes devices pair and sign in
/// through, so the routes Hive answers without a session stay the same few. Every route under
/// `/scout/` is for a Scout's session only.
public enum ScoutEndpoint {
    /// The first part of every route only a Scout's session reaches.
    public static let routePrefix = "scout"
    public static let health = "/health"
    /// `POST` a `ScoutEnrollmentRequest` to enroll through the server's open window. Answers 404 for
    /// every request without a good token, as if it weren't there.
    public static let enrollment = "/pairing"
    /// `POST` gives a `ScoutSignInChallenge`.
    public static let signInChallenge = "/sign-in/challenge"
    /// `POST` a `ScoutSignInRequest` for a `ScoutSession`.
    public static let signIn = "/sign-in"
    /// `GET` reads the `ScoutSessionCheck` of the session it's sent with.
    public static let session = "/scout/session"
    /// `POST` a `MetricsReport` for the session's server. Answers 2xx once it's kept, 422 with a
    /// `ScoutRefusal` for what it won't keep, 429 when it's sent too often, 409 with a
    /// `ScoutProtocolMismatch` when Scout has to be updated, and 503 when Hive couldn't keep it.
    public static let metrics = "/scout/metrics"
}

/// Which version of what Scout sends to Hive. It goes up only when that changes, apart from Scout's
/// own version. Hive accepts the current one and the one before it, so Scouts can be updated when it
/// suits you.
public enum ScoutProtocolVersion {
    public static let current = 1

    public static func isAccepted(_ version: Int) -> Bool {
        version == current || version == current - 1
    }
}
