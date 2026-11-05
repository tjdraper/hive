# A4. Secure Enclave keys and secrets

**Phase A — Foundations** · Engine, 1 session, installed build, needs you

References like §7 point to [00-Info.md](00-Info.md). Read the brainstorm's "Secrets and keys at rest".

## Check first

Before building on it, confirm the open question in §19: in the installed daemon, after it switches user and with nobody logged in, create a Secure Enclave P-256 signing key and key agreement key, save their `dataRepresentation`, then load them again after a restart, sign, and do an ECDH exchange.

Two things that may get in the way:

- **Access control:** CryptoKit's default protection may need the Mac unlocked by a logged-in user. Set the keys' access control explicitly to one that works with nobody logged in.
- **Entitlements:** a bare command-line executable may be refused Secure Enclave keys (`errSecMissingEntitlement`). If so, the daemon may need to be a small app bundle inside `Hive.app`, with its own provisioning profile.

If it still fails, stop and decide with you how §7 changes before going further. It may change A2's design too.

## Then

- **The identity key and the storage key** (§7), created on the first start after switching user, and stored as `0600` files in the data directory. B1 uses the identity key.
- **Encrypting secrets:** a temporary key, ECDH with the storage key, HKDF, then AES-GCM, in a small versioned format so it can change later. It lives in HiveCore, behind a protocol for the key agreement, so tests use software keys and the daemon uses the Secure Enclave.
- **Logging:** whether keys were created or loaded. Never key material.

## Tests

- A secret encrypted and decrypted again matches
- A changed byte anywhere in the stored secret fails to decrypt, never decrypting to something else
- A secret encrypted for one storage key can't be decrypted with another
- An unknown format version is refused

**Done when:** the "check first" passes; the installed daemon creates both keys on first start and reuses them after restarts and a reboot with nobody logged in; a test secret written in one run decrypts in the next; and the tests pass.
