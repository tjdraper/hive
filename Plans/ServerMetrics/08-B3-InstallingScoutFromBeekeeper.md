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

## Session 1

Done: the engine, and what Scout needed for it. Beekeeper's screens come next, with you. `Scripts/build-and-test.sh` passes, run from Terminal at Ivy's screen: over SSH, macOS keeps the Keychain from Sparkle's tools and codesign. Not yet checked in the test VMs.

What was decided along the way:

- **Two routes,** driven from the Developer window until the screens exist. `POST /servers/:id/scout-check` answers `ScoutCheckResult` (HiveKit): the SSH user, the CPU, `ScoutRootAccess` (root, `sudo`, `doas`, Scout's `sudo` or `doas` rule, or none), whether `sudo` or `doas` is installed, whether Scout is installed and its version, and what's in the way (not Linux, another CPU, another init system). `POST /servers/:id/scout-action` with a `ScoutAction` (install, update, enroll again, send addresses, uninstall) answers `ScoutActionResult`: done, refused or failed, with Hive's reason, the connection failure, or Scout's own message, cut at 2,000 characters.
- **The probe** (`ScoutInstalling/ScoutProbe.swift`) is one constant `sh -c` script. It asks the installed Scout its version as root, through `sudo -n` or `doas -n`, which also finds Scout's rule; `sudo -n true` and `doas -n true` find passwordless access. Hive keeps only the lines it recognizes, and a version only as a release writes it, from a Scout for the server's own CPU. Its tests run the script with `sh` on the Mac among stand-ins for `uname`, `id`, `sudo`, `doas` and Scout.
- **Every command** is built in `ScoutManagementCommand` from Hive's own words: Scout's `manage` behind `sudo -n` or `doas -n` where needed, and for install a script that reads the request line and then the binary from standard input, keeps the binary in a `mktemp -d` folder, checks its SHA-256 (from Hive.app), and pipes the request to its `manage` as root. The code goes only on standard input.
- **Install** needs root, passwordless `sudo` or passwordless `doas`, and no Scout already installed; Hive checks the binary in Hive.app is the one its statement names, opens an enrollment window in the same confirmed action, and closes it again if Scout doesn't finish. **Update** goes through `manage` with any access, the rule included, only when Hive.app's version is newer. **Enroll again** sends a new code to the installed Scout's `manage`, confirmed. **Uninstall** also removes the server's metrics, so its key stops working.
- **New addresses:** Scout 0.2.0 adds `manage`'s `addresses` request, which saves the Hive's address options into the enrollment as Scout's own user (`hive-scout addresses`, run as a program of its own, as `enroll` is), keeping the key and pin, and reloads the service. A 0.1.0 Scout refuses it as a request it doesn't understand, so it needs updating first. Scout's version is now 0.2.0.
- **Confirmation** for install and enroll again is the enrollment window's, asked before Hive connects at all.
- **The audit log** gains `installed`, `updated`, `addressesSent`, `uninstalled` and `actionFailed` for Scout. Enrolling is still recorded when the Scout enrolls, and uninstalling also records the metrics removed. Something Scout refused changed nothing and isn't recorded.
- **The binaries** come from `Contents/Resources/Scout` beside the daemon (`CarriedScout`).
- **AGENTS.md** gains the rule this slice asked for.

Left for the UI session:

- Add Metrics checks the server first and offers Install, B2's command with `--ssh-user` and the reason, or what's in the way; Update, Uninstall and Enroll Again over SSH on the server's metrics; Update All, and where it goes, since the dashboard is B5's; and when to offer sending new addresses, since Hive doesn't keep which addresses each Scout has.
- An action is one request, which `URLSession` gives up on after 60 seconds without an answer. Installing 20 MB over a slow link could take that long; time it in the VMs.
- `mktemp -d` puts the install's binary in `/tmp`, which some servers mount `noexec`, as B2's command does.

## Session 2

Done: Beekeeper's screens, and the checks in the test VMs. B3 is done.

What was decided along the way:

- **Add Metrics** checks the server first where Hive signs in to it (`ScoutInstallChoice`). It offers Install, or Enroll when Scout is already there and Hive can manage it, with "Show Command Instead" beside either. Otherwise it shows B2's command with the reason. The command gets `--ssh-user` only when the server has `sudo` or `doas`, since otherwise Scout's rule can't help. Where Scout can't run, the sheet says what's in the way. When the check itself fails, the sheet says why and shows the command.
- **The server's metrics** gain Update Scout when an update is offered, and Uninstall Scout… in place of Remove Metrics wherever Hive can manage Scout. They also gain "Give Scout the Hive's Addresses", offered whenever Hive can manage Scout, since Hive doesn't keep which addresses each Scout has. Each action's progress and outcome show in a row under them (`ScoutActionStatus`).
- **Update All** sits under Servers on the Hive's overview until B5's dashboard. It updates the out-of-date Scouts one after another and lists each server it couldn't update, with the reason. The overview loads which Scouts are out of date, since a view that shows nothing never runs its tasks.

Checked in the test VMs, driving Debug Beekeeper:

- **Debian, signed in as root:** Install, then update to a 0.2.1 build through Update All, then Uninstall. Scout ran as `hive-scout`, the install's temporary folder was removed, and uninstalling left no binary, service, data or user.
- **Debian, signed in as `deploy` without `sudo`:** Add Metrics showed the command, with the reason. After the command ran, the `sudo` rule was one line, which `visudo -c` accepts. Update and Uninstall from Beekeeper worked through it, and uninstalling removed the rule.
- **Alpine, signed in as `deploy`, with `doas`:** the same, through `doas` and OpenRC.
- **Timing:** installing over SSH took a few seconds on the VMs, far inside `URLSession`'s 60 seconds.

Follow-ups:

- On a slow link, sending 20 MB could still pass 60 seconds, which ends the request in Beekeeper while Hive finishes. If it happens, move installing and updating to a job Beekeeper watches.
- `mktemp -d` puts the binary in `/tmp`, which some servers mount `noexec`, as B2's command does.
- Add Metrics' sheet keeps one size, so the Install offer leaves space below its text.
