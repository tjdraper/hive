# E1. Sending email

**Phase E — Email** · Mixed, 1 session

References like §13 point to [00-Info.md](00-Info.md).

- **SMTP** (§13): host, port, STARTTLS or implicit TLS, username, password and recipients. Choose a library or write a small client over SwiftNIO (§19). The server's certificate is checked against the system's trusted certificates, with no option to skip it.
- **The password is a secret,** stored encrypted and write-only (§7). Changing the host clears it, and needs confirmation (§6), so a stolen session can't send it somewhere else.
- **Sending:** retried with a growing delay when the provider is unreachable, with failures in the system log, never message contents
- **Settings in Beekeeper** and Send Test Email, built with you

## Tests

- The messages Hive builds are valid, including non-ASCII names in the subject and body
- The password never appears in a response, the audit log or the system log
- Changing the host clears the password

- **From D4:** a confirmed route reads its request with `ConfirmedRequest.read` and checks `ConfirmationRequirement.check` inside the store's write transaction, against the stored values. Add the new `ConfirmationReason` to HiveKit, its Touch ID wording to `ConfirmationReason.prompt`, and a case to `ConfirmedRouteTests.cases`, which covers the refusals. In Beekeeper, send it with `HiveLink.confirmed(_:_:body:reason:)`, giving a `reason` when the change is known to need confirming.

**Done when:** a test email sent from Beekeeper arrives through your own provider, and the tests pass.
