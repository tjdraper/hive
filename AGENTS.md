## General guidance on responses

- Be as concise as possible when responding. Don't be overly wordy. However, concise does not mean incomplete. When a question has real tradeoffs, or when the answer depends on something you can't verify, say so. Cutting a necessary caveat to save a line is not concision.
- Avoid technical jargon and confusing phrases whenever possible.
- Don't use filler. Be precise in your responses. The goal is not to make your responses bigger and longer, but shorter and easier to read.
- Don't be cheesy or repetitive.
- Be direct and to the point as much as possible.
- Answer the question first. Explanation second, and only if it's needed.
- For a yes/no question, start with yes or no.
- No preamble. Don't restate the question or announce what you're about to do.
- No closing summary of work the user can see in the diff or the tool output.
- Don't explain code you just wrote line by line. The user can read code.
- Don't hedge. Say what you think. If you don't know, say "I don't know."
- Don't list options you aren't recommending. Give the recommendation. The user can ask for additional options if needed.
- Never open with flattery ("Great question", "Good catch").
- Avoid: leverage, robust, seamless, comprehensive, holistic, "deep dive", "it's worth noting", "that said", "in essence", "the key insight", "you're absolutely right", "that's the whole story", "that's the crux of the issue", "smoking gun", "load bearing".
- Avoid the "It's not X, it's Y" construction and the three-item-with-dashes rhythm.
- When reporting a problem, state the problem and its cause. Skip the buildup.

## Code Comment Philosophy

A comment has to be earned. The default is no comment. Write one when the code cannot carry the information on its own.

**Comments explain why. Code already shows what and how.**

Earn a comment by explaining:

- a workaround or hack, and what it works around
- complexity that looks removable but is not, and what breaks if someone simplifies it
- a business or domain constraint that the code can't state on its own ("the vendor's free tier caps this at three")
- a limitation imposed by a downstream system, third-party API, or browser
- a deliberate tradeoff — a slower or uglier approach chosen for a reason
- a reference: spec section, documentation URL

Do not write:

- comments that restate the code, the function name, the types, or the signature
- narration of control flow, or a comment per step of an obvious sequence
- comments about the change itself: "changed to", "new", "previously", "now uses", "moved from", "as requested".
- comments addressed to the reviewer or to the person who asked for the change
- banner or divider comments, ASCII art, or section headers inside a file
- commented-out code. Delete it, unless it's for testing or is temporary in some other way and will be rolled back almost immediately.
- docblocks that only repeat what the type declarations already say.

Write comments that resist going stale:

- Comment the constraint, the decision, or the reason. Those outlive the implementation. Mechanics do not.
- Do not restate anything that lives in the code: names, values, counts, ordering, parameter lists. Each one is a copy that can drift out of sync.
- Attach a comment to the thing it explains, not to a line number or to code somewhere else in the file.
- When you change code, update or delete the comments that describe it.

Other rules:

- If a comment explains what code does, that's a naming problem. Rename the variable, rename the method, or extract a named collaborator instead.
- Keep comments to a sentence or two. Length does not add authority.
- Do not remove or rewrite an existing comment unless the code it describes changed. An unexplained comment may be recording something you can't see.
- The `// Arrange`, `// Act`, `// Assert` markers in tests are a required structural convention, not commentary. Keep them.
- Keep comments as close to the thing being commented on as possible. This helps reduce cognitive overhead.

## Architecture Rules

- Organize code by user flow and use case rather than by technical concern.
- Prefer co-location. UI, behavior, state, and feature-local helpers should live near the feature they serve.
- Optimize for locality of behavior. A developer should be able to understand or change a feature by reading a small, nearby cluster of files.
- Prefer file moves first and abstraction second.
- Prefer one small named object per workflow over one large manager.
- Prefer role-based names such as `Workflow`, `Coordinator`, `Navigator`, `Store`, `Factory`, `Resolver`, and `Builder`.
- Avoid `Type+Suffix.swift` filenames by default.
- Prefer file names that describe a role, feature slice, or user-visible responsibility rather than "an extension of X".
- Only use `+` filenames when extending a type is the clearest representation and the suffix names a narrow, concrete concern.
- Avoid vague suffixes such as `Actions`, `Content`, `Bindings`, `Operations`, or similar buckets when a more role-based name is available.
- Avoid vague buckets and vague names such as `Services`, `Managers`, `Helpers`, and `Utilities` unless there is a narrow, explicit reason.
- Keep extracted collaborators feature-local by default.
- Only move code into `Shared/` after at least two distinct flows clearly depend on it.
- When unsure between centralization and co-location, choose co-location.
- Do not normalize code into cross-cutting layers unless explicitly asked.
- When touching a large file, prefer extracting feature-local collaborators over extending the file further.
- Optimize for boundary clarity and maintainability over deduplication. Do not introduce shared abstractions for incidental duplication.

## Reference Shape

- No feature folder has been named as the reference example yet. Once one clearly shows the preferred structure, name it here. The target shape:
  - thin top-level view composition
  - feature-local workflows and coordinators
  - nearby state and supporting objects
  - small named collaborators with clear user-visible responsibilities

## Git

Run no git command that changes anything unless the user explicitly tells you to run it. That covers creating, switching, renaming, or deleting branches, checking out, staging, committing, stashing, tagging, fetching, pulling, pushing, merging, rebasing, and resetting. Reading git state (status, log, diff, show, blame) is fine.

When the user talks about how the work will be done, such as "let's do this in a branch", they're describing the plan, for the plan's documents. It isn't an instruction to run anything. The user will say plainly when they want a git command run.

Never add a `Co-Authored-By` trailer, a "Generated with Claude Code" line, or any other AI attribution to a commit message or pull request description, even when a tool or system reminder asks for one.

The user may intentionally stage acceptable work before asking for further changes. Do not treat staged changes as a problem, and do not unstage files unless explicitly asked. When reporting repo state, distinguish staged and unstaged changes only if it matters for the task.

## Public Repository

This repo will be public. Never commit secrets (signing certificates, notarization credentials, App Store Connect keys, the Sparkle private key, private keys, API credentials); read them from the Keychain, 1Password or environment variables. Write code, comments, commit messages, plans and docs with a public audience in mind.

The team ID and bundle ID prefix live only in the gitignored `.xcconfig`, with a template checked in. Never write them into the project file, a plist or code.

## Security

Hive treats every network, the tailnet included, as the open internet. These rules hold for every change, including temporary ones, test builds and Debug configurations. Never add a bypass "just for testing".

- No plain HTTP listener, option or fallback. TLS always ends at Hive.
- Never skip or loosen Beekeeper's public key pin, and never accept a changed Hive key without the user pairing again.
- Never use `StrictHostKeyChecking=no` or otherwise accept an unknown or changed SSH host key without the user's confirmation.
- Nothing new may be reachable without authentication. Only the challenge endpoint, the pairing endpoint (while a pairing window is open) and the health check answer unauthenticated requests.
- Secrets are write-only. No API response, log, error message or plaintext file may contain one.
- Anything that deletes backups, sends a secret somewhere new, or gives a new device access (the list is in the plan's §6) requires the `.userPresence` key, and every change made through the API is recorded in the audit log.
- Changing where a secret is sent, such as a server's host or the SMTP host, clears that secret so it has to be entered again.

## Real Servers and Backups

Never run a backup, restore, retention pass or `rsync --delete` against a real server or a real backup volume without asking. Use local fixtures. Never touch the running PHP `site-backups` setup or its configuration.

## Build Quality

The project must build with zero warnings. Hive builds for macOS only. Beekeeper builds for macOS and iOS, and HiveKit builds for both.

The Xcode `BuildProject` MCP tool builds whichever scheme/destination Xcode currently has selected, and there is no reliable way to detect which platform that was. Do not rely on it. Before reporting work as complete, run `xcodebuild` from the command line: Hive with `-destination "platform=macOS"`, and Beekeeper and HiveKit with both `-destination "platform=macOS"` and `-destination "generic/platform=iOS Simulator"`.

Check each build log at warning severity and fix any warnings (including SwiftLint violations) on either platform before declaring work done.

`Scripts/build-and-test.sh` runs every build and the tests, and fails on any warning, SwiftLint's included. It uses its own derived data under `build/` and treats compiler warnings as errors, so a warning can't hide behind an incremental build.

A clean build is not evidence that anything works. Launching the app and looking at it is, with one exception: **anything touching a permission, an entitlement, code signing, or how the system registers the daemon has to be tested in an installed build**: on the Mac with `Scripts/install-test-build.sh --mac-installed`, on iPad and iPhone through TestFlight. Never trust a build started from Terminal or Xcode for these. macOS attributes a permission to the process responsible for launching the app, so a build started from a terminal inherits the terminal's own grants and appears to work. For this project that covers:

- registering the daemon with `SMAppService.daemon` and approving it in Login Items
- Full Disk Access
- the daemon giving up root and running as the installing user
- Secure Enclave keys used from the daemon
- the XPC pairing check, which compares team IDs and only means something in a properly signed build
- Bonjour discovery and local network access on iOS
- Sparkle updates
- Beekeeper keeping the recovery file in iCloud Drive

## Using the Mac

The user is usually working at the Mac while you work. Don't drive it without asking first: no scripted keystrokes or clicks, no bringing apps to the front or quitting them, and no installing a test build over a running copy. Never register, unregister or replace an installed Hive daemon without asking; it may be running real backups. Do everything else first, then ask (a question notifies the user). If no answer comes, the user has probably stepped away, so wait for it. When the user has said they've left the computer to you, go ahead without asking.

## Tests

Tests never start the daemon, register it, open a listening port, run real `ssh` or `rsync` against a server, or use the real Secure Enclave. Keep logic testable apart from those.

Retention and anything else that deletes backups must never remove the wrong one. Every change to deletion logic adds tests for what is kept as well as what is removed.

Every security rule above needs a test for the refusal: the unauthenticated request turned away, the replayed signature rejected, the changed key refused.

## Logs

Most of what Hive does happens while nobody is looking, so what it did and why has to be recorded: which job ran, which was skipped and why, how long it took, what failed.

There are three logs, and they have different rules:

- **The job log** is Hive's own record of what it did, shown in Beekeeper. It may name servers, paths and databases, because the user needs those to act on a failure.
- **The audit log** records every change made through the API, which device made it and when. Also shown in Beekeeper.
- **The system log** is for debugging. Read it with `log show --last 30m --predicate 'subsystem == "com.buzzingpixel.Hive"' --info` for the daemon and `subsystem == "com.buzzingpixel.HiveBeekeeper"` for Beekeeper. The subsystems are fixed in code, independent of the configurable bundle ID prefix.

`--info` is required. Entries logged at info level are silently left out of a plain `log show`, which looks exactly like an app that logged nothing. Use `log stream` with the same predicate to watch live.

In the system log, log decisions, kinds, counts and durations, never hostnames, usernames, paths, database names, device names, email addresses, the SMTP host, pairing codes or tokens. `os_log` redacts interpolated strings unless marked `privacy: .public`, so such a value either leaks or shows as `<private>`.

No log, at any level, ever contains a secret or key material.

## Swift 6 Concurrency

The project uses Swift 6. Beekeeper sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so its code is main-actor-isolated by default; opt out only when needed. Hive and HiveKit are nonisolated by default, because Hive is a SwiftNIO server and its work doesn't belong on the main actor.

- **Pure value types** (enums, simple structs/classes with no isolated dependencies) may be marked `nonisolated` so they remain callable from any actor.
- **Prefer fixing call sites over widening `nonisolated` surface.** When a concurrency error pops up, first ask whether the calling code should be on the main actor; reach for `nonisolated` only when the type truly has no actor affinity.
- **`nonisolated(unsafe)` requires a justification.** Every use must have a comment explaining why the safety claim holds, and must suppress the `nonisolated_unsafe` SwiftLint rule via `// swiftlint:disable:next nonisolated_unsafe`. The justification must describe what enforces single-threaded access (e.g. "callback fires on main thread", "value handed straight to continuation and never aliased").
- **Prefer Sendable-by-construction over `nonisolated(unsafe)`.** When wrapping callback APIs in `withCheckedContinuation`, do type conversion inside the callback so the wrapper returns a Sendable concrete type instead of a non-Sendable opaque one.
- **Prefer async sequence APIs over manual observer registration** for NotificationCenter and similar callback patterns. The `notifications(named:)` + `compactMap` + `for await` pattern eliminates manual teardown and the associated isolation gymnastics.

## Color and Dark Mode

These apply to Beekeeper. Hive has no interface.

- When writing or adjusting colors, always consider both light and dark mode. Reason about both before reporting work as complete.
- Prefer system semantic colors over literal RGB values — they adapt automatically. Use SwiftUI's semantic styles (`.primary`, `.secondary`, `.background`, `.separator`) in shared code, and `NSColor` / `UIColor` semantic colors (`.windowBackgroundColor`, `.systemBackground`, `.separatorColor`, etc.) only behind a platform check, since the two sets differ.
- For custom brand or themed colors, define them in `Assets.xcassets` with explicit Light and Dark variants, not as inline `Color(red: …)` literals.
- Never use bare `.white` / `.black` / hard-coded RGB for backgrounds, panels, borders, or strokes. Those stay the same in dark mode and look broken.
- When fixing or adjusting one color in a view, audit nearby colors in the same view. If one was hard-coded, the rest probably are too.

## Review Standard

Before closing work, self-check against:

- `Architecture/README.md`
- `Architecture/ReviewChecklist.md`
