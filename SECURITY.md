# Security

## Reporting a vulnerability

Report it privately through [GitHub's vulnerability reporting](https://github.com/tjdraper/hive/security/advisories/new), not in a public issue. Include the version, what an attacker needs (network access, a paired device, an account on the Hive Mac) and what they gain.

Fixes go into the next release. Only the latest release is supported.

## The security model

Hive holds SSH keys and database passwords for your servers, and copies of everything on them, so it's built on the assumption that every network it's on, a VPN like Tailscale included, is the open internet.

**Connections.** Every connection to Hive is TLS 1.3. There's no plain HTTP mode. Hive's TLS key is in the Hive Mac's Secure Enclave and can't be copied off it. Beekeeper pins that key when it pairs and refuses any other, so a changed key means pairing again, never a warning to click through.

**Devices.** Each device that pairs makes its own key in its Secure Enclave and signs in by signing a fresh challenge with it. There are no passwords to guess or reuse. Without signing in, Hive answers only a health check, a sign-in challenge, and pairing while a pairing window is open. Failed sign-ins and pairing attempts are rate limited per address and per device. Any paired device can revoke any other.

**Pairing.** The first device is Beekeeper on the Hive Mac, which pairs over a local connection that Hive accepts only from a Beekeeper signed by the same developer team as Hive. Every other device pairs with a single-use code that expires after about five minutes, from a pairing window opened on a device that's already paired.

**Confirmation.** Actions that delete backups, send a secret somewhere new or give a new device access need Face ID, Touch ID or the device's password, even in an open session. Changing a server's host, port or user, or the email server's host, clears the password that went with it, so a stolen session can't point Hive at another machine and collect it.

**Secrets at rest.** Each secret is encrypted with a key in the Hive Mac's Secure Enclave. A copy of Hive's data folder can't be opened on any other Mac. Secrets can be written through Beekeeper but never read back, and they never appear in a log.

**The daemon.** Hive runs as a LaunchDaemon so it starts at boot, then gives up root for good and runs as the user who installed it. It refuses to start from a `Hive.app` that anyone but root can change.

**SSH.** Hive makes a separate SSH key for each server. It connects only after you've confirmed the server's host key, and never to a server whose host key has changed until you confirm the new one. Keys reach `ssh` through an agent Hive starts for each connection, never a file. Database passwords never appear on a command line, on the Mac or the server.

**Recovery.** Recovery files hold every secret, encrypted to a recovery key that Hive never has: Beekeeper makes it, shows it once for your password manager, and gives Hive only the public half.

**What it doesn't protect.** Snapshots on the backup drive aren't encrypted. They hold your servers' files and database dumps, so anyone with the drive, or with your account on the Hive Mac, can read them. Keep the drive somewhere only you can reach.
