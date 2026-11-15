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
