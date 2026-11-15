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
