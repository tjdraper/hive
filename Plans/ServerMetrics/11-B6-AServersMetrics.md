# B6. A server's metrics

**Phase B — Metrics in Beekeeper** · UI, 2 sessions

References like §7 point to [00-Info.md](00-Info.md). Load the `dataviz` skill before the first chart.

Built with you, starting from §7. A natural split: the server's page in the first session, the pages for each kind of figure in the second.

- **The server's page:**
  - what it is: distribution, kernel, cores, memory, uptime, Scout's version, and warnings when its clock is off or its processes are hidden
  - a range from an hour to a year, with the charts sharing one time axis and one selected moment
  - CPU split into user, system, I/O wait and steal; load against the number of cores; memory and swap; pressure, where the server has it; each disk's use; disk activity; the network
  - each chart drawing the average with the highest above it, and the lowest where it's kept, so a spike averaged away still shows
  - backup runs marked across the charts
  - choosing a moment shows the processes then
- **Pages for each kind of figure:**
  - processes: live, grouped by command (§4), with a choice to see each process instead, and grouped memory labelled as approximate
  - each disk: use, inodes, activity, and when it fills (B4)
  - the rest as they earn a page of their own
- **Live** while the range ends now

**Done when:** you can find, on the test VM, the process behind a CPU spike made with `stress-ng` an hour earlier, and the forecast for a filesystem being filled on purpose; you're happy with the pages on the Mac in light and dark; and the build is clean.

## Session 1

Done: the server's page. Session 2 has the pages for each kind of figure and the rest of the "done when".

Checked on Ivy with the development Hive (2026-11-24): the Debian VM's Scout (B3 Debian root), opened from its dashboard card. A `stress-ng --cpu 4` run showed as a 42% spike in CPU and a rise in load, and clicking it showed `stress-ng-cpu ×4` at 400% CPU, as root. The Day range showed the spike in the highest line where the 3-minute averages flattened it. Light and dark approved on the Mac.

That check found a B4 bug, now fixed with a test: a range starting partway through an hour read that hour's row, which also counts samples from before the range, as holding more than the 10-second rows in the range. So the whole stretch up to the next hour showed the hour's figures. Every resolution is now read from where the coarsest one's first row starts.

What was decided along the way:

- **Where it lives:** `ServerMetricsPage/`, a sidebar item of its own (`serverMetrics`), reached from a dashboard card and from Show Metrics in the server's page. Its path is Hive › Metrics › server. The sidebar highlights nothing while it shows, since it isn't a row.
- **What it is:** distribution, kernel, cores, memory, uptime and Scout's version along the top, with warnings when the clock is more than a minute off or processes are hidden. Uptime comes from Hive: `ScoutState.startedAt`, the newest sample's time less its uptime. It's optional, so the API version stays at 4.
- **Range:** Hour, 6 Hours, Day, Week, Month and Year in the toolbar, always ending now. It's read again every 10 seconds for an hour and every minute for the rest. Moving the range into the past waits until someone needs it.
- **Charts** (Swift Charts), each with a legend reading the figures at the moment shown, or the newest:
  - CPU stacks user, system, I/O wait and steal, with a dashed "Highest" line on buckets longer than 10 seconds. That line adds up each part's highest, so it can overstate when the parts peaked at different times.
  - Load against a dashed line at the number of cores.
  - Memory in use and cache, scaled to the total. In use's band comes from available's lowest and highest.
  - Swap in use and pages swapped in and out, only where the server has swap.
  - Pressure, only where the kernel reports it.
  - Each filesystem's share used, as `df` shows it.
  - Each disk's read and written bytes, and each interface's received and sent bytes.
- **Highest and lowest** show as a faint band around each average line. Backup runs are shaded grey across every chart, red where they failed, and the legend names the job at the moment shown.
- **The moment:** the pointer over any chart moves a dashed rule across all of them, and a click puts a solid one there and opens the processes at that moment in an inspector. Either CPU or memory order; an hour's top groups show their average and highest.
- **Byte axes** step in whole binary units (0, 2, 4, 6 GB).

Follow-ups:

- **The processes page, each disk's page with its forecast, and the "done when"** (finding a spike an hour old, and a filling filesystem's forecast) are session 2.
- **Containers' processes show a numeric user,** such as `postgres` as 70, since Scout looks the ID up on the host. B7 already has this.

## Session 2

Done: the processes page and each filesystem's page, and the "done when".

- **Processes** (`ProcessesPage`), from Processes beside the CPU and Memory charts: CPU and the number of processes and zombies over the range, and below them a table of the groups, live every 10 seconds, or at the moment clicked on either chart, with Show Live to go back. Columns sort; CPU under 10% of a core shows a decimal, since most groups would otherwise all read 0%.
- **Each filesystem** (`FilesystemPage`), from its mount point beside Disk space used: device, type, size, used, available and free inodes; the forecast (B4), orange when it fills within a week; space used, inodes used, and the activity and busy share of the disk it's on. Loop devices and those layered on disks, such as LVM's, have no disk of their own in Scout's figures, so they show no disk charts. It opens on Day, since filling is slow.
- **Hive sends each filesystem's device and type** with its series, from what it already kept, so the page needs no new route.
- Both are `figurePage` sidebar items, under the server's metrics page in the path.
- **Each process on its own is left for later** (§4). Scout sends only the top groups, so it needs a protocol change, not a page.

Checked on Ivy with the development Hive (2026-11-24), on the Debian VM's Scout (B3 Debian root):

- **The spike:** `stress-ng --cpu 2`, run as `deploy` at 18:47. At 19:50 the processes page's 6 Hours range showed it, and clicking it showed the sample at 18:48:30 with `stress-ng-cpu ×2`, `deploy`, 200% at the top.
- **The forecast:** `/home` filled 12 MB every 5 minutes by `scout-test-fill.service`, which stops at 300 MB free. Its page showed a forecast from the first hour of filling, "fills in 2 weeks", slowed by the flat hours before it began in the week's figures. The forecast once more hours had filled was left to everyday use. `/` showed "fills in 3 days", which is real: the VM's btrfs disk is shared with OrbStack's other machines.
- **Light and dark** approved on the Mac.
