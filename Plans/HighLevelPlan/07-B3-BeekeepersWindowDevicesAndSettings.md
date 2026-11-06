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
- **Signing in again** without asking when a session runs out, after 15 minutes, or a request gets 401 (B2)
- **A Developer window,** in Debug and `TEST_BUILD` builds only, that sends any API request as the signed-in device and shows the response. Phase C's checks go through it before Phase D's screens exist. It signs in like everything else and gets no extra access (AGENTS.md).

**Decisions (2026-11-06):**

- **The routes:** `GET /hive` gives the Hive ID, its name and whether it has Full Disk Access, checked at each request since it can be turned off while Hive runs. `GET /devices` lists devices oldest first, and `DELETE /devices/<id>` revokes one and ends its sessions at once; a device may revoke itself. `GET /settings` gives the settings, the Mac's addresses and what Hive is listening on right now, and `PUT /settings` takes the whole settings. `GET /audit-log` is newest first, a page at a time with `?before=<id>&limit=<n>`.
- **The audit log** is a table of its own. Each entry is written in the same transaction as the change it records, names the device that made it, and keeps a copy of the device's name so it reads the same once the device is revoked. Pairing on the Hive Mac, revoking, renaming, and changing the listen address and port are its entries so far.
- **The Hive's name** starts as the Mac's name from System Settings › General › Sharing, and goes through the same check as a device's name.
- **Listening:** the setting is this Mac only, this Mac and one address, or all addresses, and Hive always listens on `127.0.0.1` too. It keeps an address rather than an interface name (§5). All addresses is the dual-stack `::`. Each address gets its own Hummingbird server, all sharing one responder. Hive checks the Mac's addresses every 5 seconds and starts or stops listening as the chosen one comes and goes. A change starts the new listeners before stopping the old ones, which finish the requests they're handling first, including the one that made the change. A port that's taken on `127.0.0.1` is turned down with 422, changing nothing. Ports below 1024 are refused, since Hive isn't root.
- **Beekeeper's store** is `Hives.json` in its Application Support folder, with each Hive's name and addresses. The pin moved into the keychain item with the device key, since a program running as you could change the file to point Beekeeper at its own key and pass the sign-in on (§3). B2's keychain items have no pin, and Beekeeper pairs again rather than reading them.
- **Signing in again** is HiveKit's `HiveSession`: it signs in when it has no session or less than 30 seconds of one left, and once more on 401, since Hive forgets sessions when it restarts. Requests that arrive during a sign-in wait for it.
- **The window:** a sidebar section per Hive with its status (connected, offline, identity changed, not paired), and Overview, Devices, Audit Log and Settings under it. Beekeeper checks every Hive every 30 seconds. When a Hive can't be shown, the page says why, with Pair Again for this Mac's Hive.
- **Pairing on the Hive Mac** is a button, in the empty list and after this device is revoked, rather than automatic, so an empty list never pairs a new device by itself.
- **The Developer window** is in Debug and `TEST_BUILD` builds on the Mac, under Window › Developer. A port changed from it isn't saved in Beekeeper's list, so Beekeeper loses the Hive until the port is changed back.

**Result (2026-11-06):** in the Debug build, against the development daemon, listening on the Tailscale address, on all addresses and back to this Mac only each took effect without a restart, and `lsof` showed exactly the listeners asked for. A port change moved the daemon to the new port after answering on the old one, and saving it from the Settings page updated Beekeeper's saved port so it reconnected. Revoking this Mac ended its session at once, its key was refused at the next sign-in, and Pair Again brought it back. Every change showed in the audit log with the device that made it. This Mac can't reach its own Tailscale IPv6 address even with a plain socket, so that address was left to a check from another device. In the installed builds, the store migrated from B2's with the Hive ID and devices kept, Beekeeper paired with no code and showed the Hive after a relaunch, and B2's old device was revoked from the Devices page. The health check from another Mac on the tailnet failed while Hive listened on a LAN address and answered once the Tailscale address was chosen. Renaming the Hive and changing its listen address showed in its audit log. The Full Disk Access warning showed when Full Disk Access was turned off, and the Developer window called the settings routes.

**Done when:** in the installed builds, Beekeeper shows this Mac's Hive after a relaunch; renaming it and changing its listen address work and show in the audit log; Hive's health check answers from another machine on the tailnet only after its interface is added; a revoked device can't sign in again; the warning shows when Full Disk Access is turned off; and the Developer window can call the settings routes.
