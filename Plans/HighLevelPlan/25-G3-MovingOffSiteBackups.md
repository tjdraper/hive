# G3. Moving off site-backups

**Phase G — Replacing site-backups** · Mixed, 1 session, needs you

References like §1 point to [00-Info.md](00-Info.md). The configuration to move is in `../site-backups/config/Dependencies/BackupConfigBindings.php`, and its setup in `../site-backups/docker/docker-compose.prod.yml`.

The first slice that touches real servers and the real backup drive. Each step against them is done with you (AGENTS.md).

1. **Install Hive and Beekeeper** on the Hive Mac from a G2 release, approve the daemon, grant Full Disk Access, save the recovery key, and pair Beekeeper on your everyday Mac (G1). Auto-login stays on (§4).
2. **Add a case-sensitive APFS volume** to the backup drive (§9), next to the PHP version's folders, if the drive is APFS. Check there's room for both while they run side by side.
3. **Enter each server once:** the PHP configuration's two hosts, by their tailnet addresses, since its host names only exist inside its containers. Add Hive's public key to each server's `authorized_keys`, and confirm each host key against the server itself, not just what the scan shows.
4. **Enter a backup job for each site** in the PHP configuration, with its directories and databases.
5. **Run alongside the PHP version** until Hive has a week of clean runs. Compare what each backed up, and restore one MySQL and one Postgres dump into a scratch container on the development Mac.
6. **Turn off the PHP version** (you): stop its scheduler. Its backups stay on the drive until you remove them.
7. **Leave your own SSH key on the servers.** The PHP version logs in with your personal `~/.ssh/id_rsa`, so removing "its" key would lock you out.

**Done when:** every site from `site-backups` is backed up by Hive on schedule, the restored dumps check out, and the PHP version is off.

## Follow-ups

- **Beekeeper doesn't move itself to Applications.** Opened from Downloads, it just runs there. macOS runs an app opened in place from Downloads from a read-only, randomized path (App Translocation), and Sparkle can't update it there. Offer to move it to `/Applications` on first launch.
- **Beekeeper can't reach a Hive at a Tailscale address.** Pairing Karrin with Ivy's Hive at `100.115.153.27` failed with `URLError -1200`. The pin check accepted the key, then App Transport Security ran the system's own trust check and refused the self-signed certificate (`ATS failed system trust`). ATS skips `127.0.0.1` and, it seems, private LAN addresses, but Tailscale's `100.64.0.0/10` isn't one of them. G1's tailnet sign-in probably went over the LAN. Fixed by turning ATS off in Beekeeper's `Info.plist`, since Hive addresses are whatever the user enters; Karrin then paired over Tailscale in an installed build. Ships in the next release.
