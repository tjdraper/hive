# B3. Beekeeper's window, devices and settings

**Phase B — Connecting Beekeeper on the Mac** · Mixed, 1–2 sessions, installed build

References like §15 point to [00-Info.md](00-Info.md).

## Engine

- **The audit log** (§12): stored, sent through the API, and written for every change from here on. Pairing, revoking and settings changes are the first entries.
- **Devices through the API:** the list with each device's name and when it was last seen, and revoking one, which ends its session at once.
- **Hive's settings through the API:** its name, the listen address and the port. Hive always listens on `127.0.0.1`, so Beekeeper on the Hive Mac keeps working, and the setting adds one interface or all of them (§5). A change takes effect without restarting the daemon, and an interface that appears later, such as Tailscale's after login, is picked up.
- **Hive's state,** for the warnings below: whether it has Full Disk Access.

## UI

Built with you:

- **The main window:** the list of Hives in the sidebar, each with whether it's connected, offline, or has a changed identity. The list holds several Hives from the start, even though only this Mac's can be paired until G1.
- **A Hive's overview,** with a warning for missing Full Disk Access, and room for D1's servers
- **Devices,** with this device marked and Revoke on the others. Revoking this device asks first.
- **The audit log,** newest first
- **The Hive's settings**
- **Beekeeper's store** (§3), so the list of Hives survives a relaunch
- **A Developer window,** in Debug and `TEST_BUILD` builds only, that sends any API request as the signed-in device and shows the response. Phase C's checks go through it before Phase D's screens exist. It signs in like everything else and gets no extra access (AGENTS.md).

**Done when:** in the installed builds, Beekeeper shows this Mac's Hive after a relaunch; renaming it and changing its listen address work and show in the audit log; Hive's health check answers from another machine on the tailnet only after its interface is added; a revoked device can't sign in again; the warning shows when Full Disk Access is turned off; and the Developer window can call the settings routes.
