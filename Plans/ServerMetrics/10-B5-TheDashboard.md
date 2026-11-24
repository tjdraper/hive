# B5. The dashboard

**Phase B — Metrics in Beekeeper** · UI, 1–2 sessions

References like §7 point to [00-Info.md](00-Info.md). Load the `dataviz` skill before the first chart.

Built with you, starting from §7:

- **Where it lives:** an entry for each Hive in the sidebar, beside its servers
- **A card for each server reporting to the Hive:** whether it's reporting, CPU, memory, swap, its fullest disk, and a sparkline of the last hour. Selecting one opens its page (B6).
- **Problems first:** servers that stopped reporting or whose clock is ahead, then any figure past its alert limit (C1 adds the limits; until then, fixed ones), then the rest by name
- **Live,** from B4's live updates
- **Colors** from the asset catalog with light and dark variants, and never color alone to say something's wrong
- **Swift Charts** for the sparklines

**Done when:** with Scouts in the test VMs reporting to the development Hive, the dashboard shows each, updates live, and moves one to the top when its Scout stops; you're happy with how it looks in light and dark; and the build is clean.

## Session 1

Done: a Metrics entry under each Hive in the sidebar, above its servers, opening a grid of cards, and the "done when". `Scripts/build-and-test.sh` passes. B5 is done; the look may change later.

Checked on Ivy with the development Hive (2026-11-24): the Debian VM's Scout (B3 Debian root) showed as Reporting with live figures and its last hour, after the two servers that stopped long ago. Stopping its service moved it to the top as Stopped within Hive's 3 minutes, its sparkline ending where it stopped; starting it again put it back as Reporting at once. Then the Alpine VM's Scout (Test: A4 Alpine) enrolled from Debug Beekeeper's Add Metrics through `Scripts/scout-test-vm.sh --alpine install --ssh-user deploy`, and both cards moved on with each sample. Their figures match, since OrbStack's machines share one kernel. Light and dark approved.

What was decided along the way:

- **Each card** has the server's name, an icon and a word for whether it's reporting, CPU with its load and cores, memory, swap and the fullest disk, each as a share with what it's of, and a sparkline of CPU and memory with a legend. A server that stopped keeps its last figures, faded, under when it last reported.
- **Order:** stopped, clock ahead or refused first; then any figure past a fixed limit from §8 (CPU over 90% for 15 minutes, memory over 90% for 10, a disk over 90%, load over twice the cores), marked with a warning icon beside the figure; then the rest, each group by name. Steal and swapping in need figures the summary doesn't carry, so they wait for C1.
- **Live:** each card takes the newer of Hive's summary and the live figures, and a server sending newer figures than a stopped summary shows as reporting at once. The summaries are read again every 30 seconds for whether each server is still reporting and for the sparkline's newest minute.
- **Colors:** CPU and memory lines from `MetricsDashboard/DashboardColors.xcassets`, with light and dark variants; a problem shows as an icon and a word as well as a red or orange border.

Follow-ups:

- **iPhone has no way to the dashboard yet,** since its Hive page is the Overview. B9 adds it as a list.
