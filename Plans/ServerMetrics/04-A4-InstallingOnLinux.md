# A4. Installing on Linux

**Phase A — Scout** · Engine, 1–2 sessions, needs you

References like §2 point to [00-Info.md](00-Info.md).

Installing by hand with a pasted command. A5 adds signed updates, and B3 installing from Beekeeper.

- **`sudo hive-scout install`,** reading the enrollment code from standard input (§2):
  - copies itself to `/usr/local/bin/hive-scout`, owned by root
  - creates the `hive-scout` system user and `/var/lib/hive-scout`, `0700` and owned by it
  - enrolls as that user, so the key is never owned by root
  - writes and starts the service: a systemd unit, or an OpenRC script on Alpine
  - refuses, saying why, on an init system it doesn't know or a server that can't reach any of the code's addresses
  - installs on a `/proc` with `hidepid`, saying processes will be hidden (§1)
- **Root never reads the state folder.** Anything as root that needs Scout's state, such as `status` or enrolling, drops to `hive-scout` first. `hive-scout` owns that folder and runs the code that talks to the network, so root must never trust what's in it.
- **Running it again** replaces the binary and restarts the service, keeping the key. Given a new code, it enrolls again and tells the running service to reload (SIGHUP), which connects at once and keeps its buffer.
- **`--ssh-user <name>`** also lets that user run Scout's management command as root (A5, B3), with nothing else:
  - `/etc/sudoers.d/hive-scout` allowing exactly `/usr/local/bin/hive-scout manage`, with no other arguments and without needing a terminal, since Hive's SSH key is added with `restrict`. Checked with `visudo -c` before it's kept.
  - `doas` instead, on a server without `sudo`, such as Alpine
  - the name checked against POSIX's portable user name pattern first, and refused otherwise, so it can't add a rule of its own
- **`sudo hive-scout uninstall`** stops and removes the service, the binary, the user, the state folder and the `sudo` or `doas` rule.
- **The systemd unit** runs as `hive-scout` with §3's caps, and locks down the rest: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, `PrivateTmp`, `PrivateDevices`, no capabilities, and only its state folder writable. Not `ProtectHome=yes`, which hides `/home` and gives a separate `/home` filesystem the wrong figures, and not `ProtectProc=invisible`, which hides other processes. OpenRC gets what it can express of the same.
- **The pasted command** downloads the binary for the server's CPU into a private temporary folder made with `mktemp -d`, checks its SHA-256, and runs the install, passing the code on standard input. A download that doesn't match stops there. No piping a script from the internet into a shell. B2 has Beekeeper build it (§2).
- **In development** the test VM script copies a development binary in, since no GitHub release exists for it.
- **A second test VM** with Alpine and OpenRC, made by a script.

## Tests

- The unit and OpenRC script written for given paths and users, compared with expected text
- The `sudo` and `doas` rules written for a given user, compared with expected text, and refused for a name outside the pattern, such as one with spaces, `#` or `ALL`
- Install refuses each case above with its message
- The code is read from standard input, and an argument that looks like one is refused
- Uninstall leaves nothing behind in a temporary root

**Done when:** in both test VMs, the pasted command installs Scout, it reports to the development Hive, survives a reboot, measures within §3's budget again, and uninstalls cleanly; a VM with a separate `/home` filesystem reports it correctly; enrolling again reconnects without a restart; with your go-ahead, the same on one real server over the tailnet to the installed Hive; and the tests pass.
