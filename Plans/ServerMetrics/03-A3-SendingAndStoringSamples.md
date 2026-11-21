# A3. Sending and storing samples

**Phase A — Scout** · Engine, 2 sessions

References like §5 point to [00-Info.md](00-Info.md).

A natural split: Scout's sending in the first session, Hive's storage in the second.

## Scout

- **`hive-scout run`:** take a sample on each 10-second mark and send it on the open connection. Sign in again when the session runs out or Hive restarts.
- **Sending is shaped for more than one kind of data** (§10): a buffer and limits for each, with metrics first. Metrics is the only kind for now, so build the seam without a second implementation behind it.
- **Every request carries** Scout's protocol version and its clock at the moment of sending (§5).
- **The buffer** (§5): the last hour whole, then for the 23 hours before, each minute's the average and highest, and the lowest only for figures where it matters (§6), nothing older. `ScoutProtocol` gains a per-minute record for these.
- **Catching up:** the newest sample first, then the rest oldest first in batches, while new samples keep coming.
- **Backing off** while Hive is unreachable, up to a minute between tries, so a sleeping Mac doesn't make every server spin.
- **Timeouts on connecting and on every request,** so a Hive that accepts a connection and then stops answering counts as unreachable rather than leaving Scout waiting. Sampling never waits on sending: a stuck request can't delay or skip a sample.
- **Refused for good** (revoked, or Hive's key changed): log it once, keep sampling into the buffer, and try again hourly. A reload after enrolling again (A2) connects at once.
- **`hive-scout status`** prints whether it's sending, when it last succeeded, and how much it's holding.

## Hive

- **`POST` for samples,** reached only by a Scout's session (A2), for its own server. The limits in §2, each refused with a reason Scout logs. Samples older than a day, or too far ahead of Scout's own clock as reported, are refused, the second as "clock ahead".
- **Scout's protocol version** on every request. Hive takes the current one and the one before (§2), and refuses older ones with a reason Scout logs and Beekeeper shows.
- **One sample per server and time:** a repeat is ignored, so a request resent after a timeout changes nothing.
- **`Metrics/metrics.sqlite`** (§6) in its own GRDB pool with explicit migrations, the `Metrics/` folder excluded from Time Machine. A table each for the server-wide figures, filesystems, disks and interfaces, at each resolution. Processes as one compressed value per sample, since they're only ever read whole for a moment.
- **Rollups:** a minute's and an hour's the average and highest, and the lowest only for figures where it matters (§6), written as each period closes and rewritten when a late batch lands in one. Per-minute records from a backlog go straight into the 1-minute resolution and feed the hour.
- **Pruning** each hour, to §6's periods.
- **The clock offset** for each server, from each request's clock, kept for B2 to show.
- **Each Scout's last-seen time and reported version and system,** updated without writing to Hive's main store on every sample.
- **History on removal** (§2): removing a server deletes its metrics; removing only its Scout keeps them.

## Tests

- Rollups of a known series, including a gap, a late batch landing in a closed period, and per-minute records from a backlog
- Pruning keeps exactly the periods in §6 at each resolution
- Each limit in §2 refuses what's over it and accepts what's at it, including new names in a day
- A Scout can't write samples for another server
- A resent batch, and a duplicate within one batch, store each sample once
- The previous protocol version is accepted, and the one before it refused with its reason
- A server's clock far ahead is refused as "clock ahead"
- The buffer keeps and drops what §5 says, keeps each minute's highest, and sends the newest sample first, then oldest first
- A Hive that never answers times out, and samples keep being taken on time meanwhile

**Done when:** a Scout in the test VM sends to the development Hive for an hour; stopping Hive for ten minutes leaves no gap once it's back; the buffer's size after a day without Hive matches §5's estimate, or §5 is corrected; the database filled with a year of made-up data for one server matches §6's estimate, or §6 is corrected; and the tests pass.

## Session 1: Scout's sending

Done: everything under Scout above, and the buffer, catching-up, refusal and timeout tests. `Scripts/build-and-test.sh` passes. Left for session 2: Hive's side, the rest of the tests, and the "done when", which needs Hive's route.

What was decided along the way:

- **`hive-scout run`** samples on each mark into a `MetricsQueue` and signals `SendingCoordinator`, which sends on its own task, so sampling never waits on a request. Both run on `ScoutEventLoop`.
- **Requests are a `MetricsReport`** to `POST /scout/metrics`: the protocol version, Scout's clock as it's sent, and up to 60 samples or 120 minutes (`MetricsMinute`, with the average, highest and `MinuteLows`). Hive's answers are written down in `ScoutEndpoint.metrics` for session 2 to follow: 2xx kept; 422 with a `ScoutRefusal` (`clock-ahead`, `too-old`, `too-many-samples`, `too-many-figures`, `too-many-new-names`, `value-out-of-range`), which Scout logs once a reason and drops; 429, which counts as unreachable; 409 with `ScoutProtocolMismatch`. Session 2 adds the route to `RequestGate.scoutRoutes`.
- **The seam for other kinds of data** is `ReportQueue`. The coordinator goes back to its first queue, metrics, after every request. `MetricsQueue` is the only one.
- **The buffer** (`MetricsBuffer`) folds samples older than an hour into minutes. A minute is closed once it's all over an hour old, and a sample on its way to Hive isn't folded until it's settled. Counts are capped as well as ages, so a clock set back can't make it grow. The newest sample goes alone first, then minutes, then samples oldest first.
- **Waiting between tries:** 10, 20, 40, then 60 seconds while unreachable; an hour when refused for good (removed, Hive's key changed at every address, or the protocol no longer accepted); 15 minutes when locked out. Another key at one address beside one that can't be reached counts as unreachable. A connection that was working and drops is opened again at once, without waiting.
- **Timeouts:** 10 seconds to connect, as before, and 30 for each request, TLS handshake included, after which the connection is closed and counts as unreachable.
- **`hive-scout status`** reads `status.json`, which the running Scout writes after every sample to its runtime folder, `/run/hive-scout` unless `--runtime-directory` gives another. `/run` is in memory, so this isn't a disk write (§3). A4's unit sets `RuntimeDirectory=hive-scout`. The status says when it's more than 30 seconds old.
- **`watch` keeps its health check.** It's for development only and doesn't send samples.
- **Left for A4,** as before: reloading the enrollment on SIGHUP.

## Session 2: Hive's storage

Done: everything under Hive above, and the rollup, pruning, limit, other-server, duplicate, protocol and clock-ahead tests. `Scripts/build-and-test.sh` passes.

Checked end to end (2026-11-21): `hive-scout run` as `hive-scout` in the test VM, with §3's caps, sent to the development Hive at `host.orb.internal:4484` for an hour, 19:45:20 to 20:45:30 UTC: 362 samples, none missing or refused, clock offset 0. Hive was stopped from 20:06:26 to 20:16:26. Scout logged once that it couldn't reach Hive, held its samples, reconnected 14 seconds after Hive started, and sent them, so each of those minutes has all six samples and the hours add up to 362. Scout's memory was 21.7 MB, 24.6 MB at its highest. The `Metrics/` folder and its write-ahead log show as excluded in `tmutil isexcluded`.

The buffer after a day without Hive, filled with the VM's own samples and measured on the Mac: 2.7 MB, and 4.0 MB with three filesystems, two interfaces and 20 process groups. §5 said about 2 MB and is corrected. The database with a year of made-up data for one server: 32 MB, as §6 says.

What was decided along the way:

- **`Metrics/`** (`MetricsDatabase`, `MetricsStore`, `MetricsRoutes`, `MetricsUpkeep`): its own GRDB pool in `Metrics/metrics.sqlite`, the folder made `0700` and excluded from backup. One that can't be opened is moved aside and a new one started, since history matters less than Hive starting. `HiveAPI`'s public init opens it.
- **Tables:** `metricsServer` (each server's clock offset, last report, newest sample's facts and last refusal), `metricsName` (each filesystem, disk and interface, with when it was first seen), and `server`, `filesystem`, `disk` and `networkInterface` at `TenSeconds`, `Minute` and `Hour`, without row IDs. `MetricsTables` lists every column once; the migration lists its own, and a test checks they agree. Totals such as memory and disk size keep only their average; available memory, space and inodes keep their lowest too.
- **Processes:** each sample's groups as LZFSE-compressed JSON in `processTenSeconds`, about 1 KB each. Each hour's top 10 by average CPU and by average memory in `processHour`, made by the hourly pass once the hour is past and again when it gained samples.
- **Rollups** run in the same transaction as the samples, for each minute and hour a request touched. The row made from more samples wins, so a repeat changes nothing, a late sample makes its period again, and a backlog minute never replaces one made from more 10-second rows. Hours weight each minute by its samples.
- **Limits** (`MetricsReportCheck`): 60 samples and 120 minutes, 4 MB a request (`too-large`, added to `ScoutRefusal`), 32 filesystems, disks and interfaces and 20 process groups a sample, 50 new names a server a day, 60 requests a server a minute (429), names up to 255 bytes without control characters, shares within 0–1 and rates within 0–10¹⁵. A sample more than 5 minutes ahead of Hive's clock or of Scout's `sentAt` is `clock-ahead`; samples over a day old are left out, and a request holding only those is `too-old`. Hive answers 503 when it couldn't keep them, which Scout counts as unreachable and sends again.
- **Last seen** stays on the `scout` row in Hive's store, written at sign-in, every 15 minutes; everything per request is in `metricsServer`.
- **Removing a server** deletes its metrics, and the hourly pass removes any a failure left behind. Removing only its Scout keeps them.
- **Measured** with a year of made-up data for one server: 32 MB, matching §6. Keeping one sample takes under 1 ms, a 60-sample batch about 12 ms, and the hourly pass about 10 ms.
