# C4. README and release

**Phase C — Alerts, Macs and release** · Mixed, 1 session, needs you

References like §2 point to [00-Info.md](00-Info.md).

- **README:** what Scout reads and costs (§3, §4); installing it from Beekeeper or by command, updating and removing it; the `sudo` rule and what it allows; that Hive has to listen on an address servers can reach; enrolling again after a restore or a new identity; and excluding `Metrics/` from Mac backups other than Time Machine (§6)
- **SECURITY.md:** what a Scout can and can't do (§1, §2), where its key lives and what root on a server can do with it, how the pasted command and updates are checked, and what the `sudo` rule lets Hive do
- **Release notes** for the version that ships it

- **The first real servers,** which A4's test VMs couldn't stand in for: they're arm64 containers sharing one kernel. Check on real servers that the x86_64 binary installs and runs as a service; that Scout starts again after a real reboot; that systemd applies the unit's lockdown itself, which OrbStack turned off and A4's script turned back on; that OpenRC's CPU and memory caps apply on a real Alpine server, where OrbStack couldn't turn on their controllers; and that samples reach Hive over the tailnet, within §3's budget.

**Done when:** a release with Scout's binaries is published, and with your go-ahead, the published Beekeeper installs Scout on a real server both ways: from Beekeeper, and by its command; the checks above pass on at least one real server, and an Alpine one if you have it.
