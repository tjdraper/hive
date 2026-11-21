import ScoutCore

/// What `hive-scout enroll` says when it fails. Never the code or the key.
enum EnrollmentMessage {
    static func text(for error: any Error) -> String {
        switch error {
        case EnrollmentError.codeRefused:
            "The Hive didn't accept the code. It may have expired or been used. Get a new one from Beekeeper."
        case EnrollmentError.lockedOut, ScoutSignInError.lockedOut:
            "The Hive turned away too many attempts from this server. Try again in 15 minutes."
        case EnrollmentError.protocolNotAccepted, ScoutSignInError.protocolNotAccepted:
            "The Hive doesn't accept this version of Scout. Update Scout, then enroll again."
        case HiveConnectionError.keyNotPinned:
            "Refused the Hive: its key isn't the one in the code. Nothing was sent."
        case let error as PrivateFileError:
            "Couldn't keep the enrollment in the state folder: \(error)"
        default:
            "Couldn't enroll: \(error)"
        }
    }
}
