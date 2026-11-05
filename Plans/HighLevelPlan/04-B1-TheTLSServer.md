# B1. The TLS server

**Phase B — Connecting Beekeeper on the Mac** · Engine, 1 session, installed build

References like §5 point to [00-Info.md](00-Info.md). Read the brainstorm's "Encryption: always TLS" and "Hardening for internet exposure".

- **The certificate:** self-signed for the identity key with `swift-certificates`, valid for 10 years, and reissued for the same key when it's missing or near expiry.
- **Signing through the Secure Enclave** with an `NIOSSLCustomPrivateKey`, so the private key never exists as a file.
- **Hummingbird 2 with TLS,** listening on `127.0.0.1` and the configured port. The listen address setting itself comes in B3. Choose the default port (§19).
- **The gate:** a check in front of routing that turns away every unauthenticated request except the health check, the challenge endpoint and the pairing endpoint (§5), before any parsing. The health check answers with as little as possible.
- **The client side in HiveKit:** a connection that checks Hive's certificate itself and compares its public key hash to the pinned one, ignoring the chain, hostname and expiry (§5).

## Tests

- The gate refuses every path not on its list, without authentication, through Hummingbird's test client
- A certificate with the pinned key passes even when expired or for another hostname, and one with a different key fails

**Done when:** the installed daemon serves TLS on `127.0.0.1`; HiveKit's client reaches the health check with the right pin and refuses a wrong one; no file in the data directory holds a usable private key; and the tests pass.
