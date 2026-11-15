# B8. Containers and services in Beekeeper

**Phase B — Metrics in Beekeeper** · UI, 1 session

References like §7 point to [00-Info.md](00-Info.md). Load the `dataviz` skill before the first chart.

Built with you, from B7's figures:

- a containers chart on the server's page, by service
- a page for containers and services: live, grouped by service, with a choice to see each container, and its processes
- containers and services beside processes at a chosen moment
- unnamed containers by short ID and the commands running in them

**Done when:** on the test VM, you can tell which Swarm service a load came from an hour later, and see a cron job's cost under its service; you're happy with the pages in light and dark; and the build is clean.
