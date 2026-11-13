// Prints a signed App Store Connect API token.
// https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
//
// Swift rather than openssl because CryptoKit gives the raw r||s signature JWT needs directly;
// openssl emits DER, which would have to be unpacked by hand.

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: asc-token.swift <AuthKey.p8> <key-id> <issuer-id>\n".utf8))
    exit(64)
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOfFile: arguments[1], encoding: .utf8))
let issuedAt = Int(Date().timeIntervalSince1970)

let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": arguments[2], "typ": "JWT"])
// Apple rejects tokens that live longer than 20 minutes.
let payload = try JSONSerialization.data(withJSONObject: [
    "iss": arguments[3],
    "iat": issuedAt,
    "exp": issuedAt + 15 * 60,
    "aud": "appstoreconnect-v1",
])

let signingInput = base64URL(header) + "." + base64URL(payload)
let signature = try key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + base64URL(signature.rawRepresentation))
