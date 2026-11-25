# B9. Metrics on iPhone and iPad

**Phase B — Metrics in Beekeeper** · UI, 1 session, TestFlight

References like §7 point to [00-Info.md](00-Info.md). Read §12 on Beekeeper's layouts.

Built with you:

- **iPad** shows the dashboard, a server's page and its containers much as the Mac does, in a narrower column when split.
- **iPhone** shows the dashboard as a list, and a server's page as one chart at a time, with the range and selected moment kept as you move between them.
- **Selecting a moment** works by touch, and processes and containers open as a sheet.
- **Leaving the app** stops live updates, as it does today, and coming back fetches what was missed.

**Done when:** on a real iPhone and iPad over the tailnet, the dashboard, a server's page and its containers work and stay readable; anything only a device can check is in a new [TestFlightChecks.md](TestFlightChecks.md) in this folder; and the build is clean on both platforms.

## Session 1

Built, and seen in the iPhone 18 Pro and 13-inch iPad Pro simulators with made-up figures (`MetricsPreviews.swift`), since a simulator can't sign in to a Hive. `Scripts/build-and-test.sh` passes. You checked the slice off with the real iPhone and iPad checks left for the release (C4), listed in [TestFlightChecks.md](TestFlightChecks.md).

They wait because the installed Hive on Ivy is 2026.4, at API version 2, and a TestFlight build of this tree needs version 4 or newer, so devices would show Update Hive for it until the release. The development Hive could stand in, but it listens only on `127.0.0.1`.

What was decided along the way:

- **iPhone reaches the dashboard** from a Metrics row on the Hive's page, above Job Log. It's a list: each server's name, its state as an icon and a word, and CPU, memory, swap and fullest disk, problems first as on the Mac. The sparkline is left to the server's page.
- **Back goes where you came from:** a server's metrics opened from the dashboard returns there, and from the server's page returns to it (`CompactNavigation`).
- **One chart at a time** on iPhone (`MetricsChartPager`), swiped between or chosen from the Charts menu in the toolbar. The range is in the page with short labels (1H to 1Y), since six full titles don't fit the toolbar. The range and the chosen moment are the page's, so they stay as the chart changes. The processes, filesystem, and containers and services pages work the same way, with lists in place of tables, and a container group's processes in a sheet.
- **Choosing a moment by touch:** a tap chooses it; touching and holding moves the rule along the chart, and lifting the finger chooses it there. On iPhone the inspector is a sheet half the screen high, which leaves the chart above it to choose another moment on.
- **iPad** shows the Mac's pages, with the chart grid's columns at least 340 points wide, down from 420, so a split view still holds a column.
- **Leaving the app** stops live updates, for the app as a whole, so one iPad window going to the background doesn't stop another's. Coming back starts them afresh, beginning with where every job stands, and every metrics page reads its figures again at once (`MetricsReloading`) rather than waiting for its next turn.

Follow-ups:

- **The TestFlight checks** in [TestFlightChecks.md](TestFlightChecks.md), moved to C4.
