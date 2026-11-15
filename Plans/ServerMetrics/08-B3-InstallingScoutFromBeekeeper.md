# B3. Installing Scout from Beekeeper

**Phase B — Metrics in Beekeeper** · Mixed, 1–2 sessions, needs you

References like §2 point to [00-Info.md](00-Info.md). Read §12 on SSH and confirmation, and the code it names.

For servers Hive already reaches over SSH (§2). Servers without SSH details keep B2's pasted command.

## Engine

- **Finding out what Hive can do on the server,** over SSH with its confirmed host key, through commands that change nothing:
  - the system and CPU, the init system, and whether `sudo` or `doas` is there
  - whether Scout is installed and at what version, from `hive-scout manage`'s status request, run as root or through `sudo -n` or `doas -n`. That also proves A4's rule works, without parsing `sudo -l`, whose output varies by version and language.
  - root access: signed in as root; passwordless `sudo` (`sudo -n true`); A4's rule; or none
  - `-n` never asks for a password, and Hive never holds or sends one
- **Acting through `hive-scout manage`** (A5):
  - **install:** where Hive has root or passwordless `sudo`, opens an enrollment window (A2) in the same confirmed action, streams the binary for the server's CPU and its signed statement over SSH, and installs and enrolls it
  - **update:** streams the new binary and statement, which the installed Scout checks before replacing itself
  - **enroll again:** after a restore or a new identity, with a new window
  - **new addresses:** when the Hive's address options change, so Scouts don't need enrolling again. The pin doesn't change, so this can't point a Scout at another Hive.
  - **uninstall:** removes Scout and A4's rule
- **The binaries come from `Hive.app`** (A5), so a server doesn't need to reach GitHub.
- **Confirmation** (§12) for install and enroll again, since they give something new access. Update, new addresses and uninstall don't need it: an update can only be a newer signed release, and uninstalling deletes no backups.
- **Update All** for every out-of-date Scout Hive can reach
- **The audit log** records each install, update, re-enrollment, address change and uninstall, and which device asked. A failure is shown in Beekeeper with Scout's message.
- **AGENTS.md's security rules** gain one: Hive installs on a server only a Scout release signed with Scout's key for that build and newer than the one already there.

## UI

Built with you:

- **Add Metrics** on a server with SSH details checks the server first, then offers one of:
  - **Install**, when Hive has root
  - **B2's command**, when it doesn't, saying why: "Hive signs in as `deploy`, which can't run commands as root. Run this once as root. It installs Scout and lets `deploy` run only Scout's own management command as root, so Beekeeper can update it from now on."
  - **what's in the way**, for a system, CPU or init system Scout doesn't support
- **Update** and **Uninstall** on the server's metrics, and **Update All** where Scouts are out of date

## Tests

- Reading each kind of root access from the probes' results, including `sudo` asking for a password, which counts as none
- Install and enroll again without confirmation are refused
- Nothing from a server's reply, or from its Scout, goes into a command Hive runs

**Done when:** on a test VM where Hive signs in as root, Beekeeper installs, updates and uninstalls Scout; on one where it signs in as a user without `sudo`, Beekeeper shows the command, and after running it, updates and uninstalls from Beekeeper work; on Alpine with `doas`, the same; and the tests pass.
