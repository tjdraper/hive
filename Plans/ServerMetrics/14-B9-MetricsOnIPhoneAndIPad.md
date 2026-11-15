# B9. Metrics on iPhone and iPad

**Phase B — Metrics in Beekeeper** · UI, 1 session, TestFlight

References like §7 point to [00-Info.md](00-Info.md). Read §12 on Beekeeper's layouts.

Built with you:

- **iPad** shows the dashboard, a server's page and its containers much as the Mac does, in a narrower column when split.
- **iPhone** shows the dashboard as a list, and a server's page as one chart at a time, with the range and selected moment kept as you move between them.
- **Selecting a moment** works by touch, and processes and containers open as a sheet.
- **Leaving the app** stops live updates, as it does today, and coming back fetches what was missed.

**Done when:** on a real iPhone and iPad over the tailnet, the dashboard, a server's page and its containers work and stay readable; anything only a device can check is in a new [TestFlightChecks.md](TestFlightChecks.md) in this folder; and the build is clean on both platforms.
