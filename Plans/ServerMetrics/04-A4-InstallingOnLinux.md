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

**Done when:** in both test VMs, the pasted command installs Scout, it reports to the development Hive, survives a reboot, measures within §3's budget again, and uninstalls cleanly; a VM with a separate `/home` filesystem reports it correctly; enrolling again reconnects without a restart; and the tests pass. The same on a real server waits for the first release with Scout (C4).

## Session 1

Done: everything above. `Scripts/build-and-test.sh` passes. Installing on a real server was moved to C4, since the installed Hive is a release from before Scout and replacing it would mean replacing the daemon running Ivy's backups.

Checked in the test VMs (2026-11-21), with codes opened from Beekeeper's Developer window:

- **Debian 12 (systemd):** install without a code kept A2's enrollment and replaced the binary and unit; install with a new code enrolled and reloaded the running Scout, same process, sending again within seconds; Scout started with the machine after `orb restart`; a separate ext4 `/home` reports exactly what `df` shows, though the unit mounts it read-only; `sudo -n hive-scout manage` works for `deploy` and nothing else does; uninstall left no file, user, group, process or `sudo` rule, and `visudo -c` still passes. `systemd-analyze security` rates the unit 3.1, "OK".
- **Alpine 3.22 (OpenRC, `doas`, no `sudo`):** install with `--ssh-user deploy` enrolled, wrote the `doas` rule and started Scout under `supervise-daemon` at nice 10 and the idle I/O class; it started again after `orb restart`; uninstall left nothing behind, its cgroup included.
- **Refusals:** not root, no code on a first install, text that isn't a code, `--ssh-user ALL`, a code as an argument, and a code whose only address can't be reached, which removed the user and folder it had made.

Measured over 5 minutes, the installed service as a server runs it:

| | Debian, 338 processes, 9 containers | Alpine, 270 processes | Budget |
| --- | --- | --- | --- |
| CPU | 0.093% | 0.063% | under 0.15% |
| Memory | 21.2 MB, 27.5 MB at its peak | 22.2 MB, 25.8 MB at its peak | goal: under 20 MB |

What was decided along the way:

- **`install` reads its code from standard input** like `enroll`, and a blank line or the end of input keeps the enrollment, so running it again only updates. It checks everything that needs no code before reading one. It enrolls by running `hive-scout enroll` as a program of its own, the code on its standard input, and `enroll`, `run` and `status` started as root switch to `hive-scout` for good before reading anything.
- **A first install that can't enroll removes the user and folder it made,** so nothing is left half done.
- **Reloading:** SIGHUP reaches `run` through a pipe the event loop reads; it ends the sending run and starts another with the enrollment read again, keeping what's held and the status. `ExecReload` sends it under systemd, and the OpenRC script's `reload` through `supervise-daemon`. Install reloads instead of restarting only when the code is new and neither the binary nor the service file changed.
- **The systemd unit locks down more than this slice listed:** the kernel's tunables, modules, logs and clock, control groups, the hostname, namespaces, realtime scheduling, set-user-ID files, writable executable memory, other system call architectures, and address families other than IPv4, IPv6 and Unix sockets, with `UMask=0077`.
- **The rules:** `sudo` allows `hive-scout manage` with no other arguments, with `!requiretty` for that command alone; `doas` allows `args manage`. The name must be POSIX's portable pattern, at most 32 characters, and not something `sudo` reads as an alias or keyword. `sudo` is used where both `sudo` and `visudo` are installed, otherwise `doas`. Each rule is checked (`visudo -c`, `doas -C`) before it's renamed into place. `manage` itself is A5's; until then it prints the usage.
- **Uninstall** stops `hive-scout`'s systemd user manager, if lingering or a login left one running, before removing the user, since `userdel` refuses a user with processes. OrbStack turns lingering on for every user.
- **The OpenRC script** sets nice and the I/O class with `supervise_daemon_args`, since `supervise-daemon` reads `SSD_NICELEVEL` only from its environment, and the CPU and memory caps with `rc_cgroup_settings`, after `want cgroups`.
- **`Scripts/scout-test-vm.sh`** makes the Alpine machine with `--alpine`, gives the Debian one a `deploy` user and an ext4 `/home`, and installs and uninstalls as the pasted command would, copying the development binary from the Mac and checking its SHA-256. OrbStack's machines are containers, and OrbStack turns off systemd's lockdown for every service in them, so the script turns Scout's back on from its own unit.

Follow-ups:

- **The OpenRC caps aren't checked yet.** In OrbStack's Alpine the CPU and memory controllers can't be turned on: the machine's init runs inside a control group that holds processes of its own, which the kernel refuses ("Resource busy"). A real Alpine server's top control group doesn't have that restriction. Check on a real Alpine server or VM.
- **One-off commands write a line to the system log,** "Failed to set thread priority for worker thread", once each time: `enroll`, and so `install`, and `sample`, as root or not. The running service doesn't. Likely Swift's runtime picking up again on a libdispatch thread after the command's work, which the server's limits don't let raise its priority. Look at it with A5's `manage`, which is a one-off command too.
