# H3. Beekeeper on iPhone

**Phase H — iPhone and iPad** · UI, 1–2 sessions, TestFlight

References like §15 point to [00-Info.md](00-Info.md).

Built with you:

- **iPhone's own layout** for the list of Hives, servers, jobs, status, snapshots and logs, and the settings and devices screens
- **Several Hives at once,** with their status in the list
- **Pairing** by scanning the QR code (H2)

- **From H1:** on iPhone, `MainWindow`'s split view collapses to the sidebar, which is empty with no Hives, with a disabled Add Server at the bottom. The first-run screen, `EmptyHiveList`, is in the detail column and never shows.

**Done when:** on your iPhone through TestFlight, Beekeeper pairs by scanning the QR code, shows live progress for a run, and deletes a snapshot on the test drive after Face ID; and the checks are added to [TestFlightChecks.md](TestFlightChecks.md).
- **From H2:** the path's compact form, icons with the page's name beneath, suits the iPhone's toolbar. Its room in `MainWindow` was measured on iPad, and the iPhone's toolbar differs. (H3: the iPhone shows no path.) The backup drive chooser keeps a minimum width of 480 on the Mac only, and hasn't been seen on an iPhone.

## Decisions

- **At iPhone width the main window is a stack,** not the split view: the Hives, then a Hive, a server and a job, each pushed on the last (`CompactNavigation`). The stack follows the sidebar's selection, so anything that selects a Hive or server goes back to it. Any compact width gets it, an iPad window that narrow included. A Pro Max iPhone held sideways may have the regular width, and would then get the iPad's split view; that hasn't been seen.
- **The first page is the list of Hives,** each with its status, and a badge when any of its jobs is running or needs a look. Servers are on the Hive's page and jobs on the server's. Nothing is selected at launch, so the list shows first. Swiping a Hive offers to remove it, and **+** adds one.
- **A Hive's page is its Overview,** with Job Log, Audit Log, Devices and Settings as rows at its end (`HivePageLinks`), each pushed over it. **+** in its toolbar adds a server.
- **There's no path in the toolbar,** since each part of it is a page the Back button returns to. Pages keep an inline title.
- **The Job Log's filters scroll sideways on iPhone and iPad,** when a long server or job name leaves them wider than the window.
- **The Overview is a grouped form on every platform,** as server and job pages are, rather than group boxes. Each warning is a section, with its buttons as rows of their own. On iPhone and iPad a server's status is under its name, since a long name beside it left both wrapping. `ViewThatFits` doesn't pick its narrower layout inside a form row.
- **A form runs nothing for a section that isn't showing:** `.task` on an empty `Group`, `Section` or `ForEach` inside a `Form` never starts. So the Overview keeps what decides whether a section shows, such as the backup drive's state (`BackupDriveWatch`) and the removed jobs (`RemovedJobList`), and the section only displays it.
- **A Hive's page starts over for each Hive** (`.id` in `MainWindow`), as server and job pages already did. Before H3, going from one Hive's Overview to another's kept the first one's snapshots of removed jobs and went on checking its backup drive.
