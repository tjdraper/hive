import CryptoKit
import Foundation
import HiveKit
import Synchronization

enum ChallengeCheck: Equatable {
    case valid
    case expired
    /// Not made by this daemon since it last started.
    case notIssued
}

/// Challenges Hive can recognize without remembering them: each carries its expiry and a MAC under a
/// key made at start. Issuing one stores nothing, so anyone may ask for as many as they like.
/// Only a challenge a paired device has signed is remembered, until it expires, so it can't be used twice.
final class SignInChallenges: Sendable {
    static let lifetime: TimeInterval = 60

    private static let version: UInt8 = 1
    private static let randomLength = 16
    private static let macLength = 32
    /// The version, the expiry as whole seconds since 1970, and the random part.
    private static let bodyLength = 1 + 8 + randomLength
    static let length = bodyLength + macLength

    private let key = SymmetricKey(size: .bits256)
    private let used = Mutex<[Data: Date]>([:])

    func issue(at now: Date) -> SignInChallenge {
        let expiry = UInt64(now.addingTimeInterval(Self.lifetime).timeIntervalSince1970.rounded(.up))
        var body = Data([Self.version])
        withUnsafeBytes(of: expiry.bigEndian) { body.append(contentsOf: $0) }
        body.append(SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) })
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return SignInChallenge(challenge: body + Data(mac), expiresInSeconds: Int(Self.lifetime))
    }

    func check(_ challenge: Data, at now: Date) -> ChallengeCheck {
        guard challenge.count == Self.length, challenge.first == Self.version else { return .notIssued }
        let body = challenge.prefix(Self.bodyLength)
        let mac = challenge.suffix(Self.macLength)
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: body, using: key) else { return .notIssued }
        return now < Self.expiry(of: challenge) ? .valid : .expired
    }

    /// Records a valid challenge as used. Returns false when it already was.
    func use(_ challenge: Data, at now: Date) -> Bool {
        used.withLock { used in
            used = used.filter { $0.value > now }
            guard used[challenge] == nil else { return false }
            used[challenge] = Self.expiry(of: challenge)
            return true
        }
    }

    private static func expiry(of challenge: Data) -> Date {
        let seconds = challenge.dropFirst().prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
