# Architecture Notes

This codebase prefers organization by user flow and use case rather than by technical concern.

## Core Principle

Keep things together that belong together.

The main goal is locality of behavior:

- related UI, state, workflows, and helpers should live near each other
- working on a feature should not require jumping across unrelated namespaces
- boundaries should reflect user-visible behavior and system capabilities

## Preferred Shape

Good boundaries usually look like:

In Hive:

- `DaemonStartup/`
- `TLSIdentity/`
- `Pairing/`
- `Authentication/`
- `SecretStorage/`
- `Recovery/`
- `DirectoryBackup/`
- `DatabaseDumps/`
- `Retention/`
- `Scheduling/`
- `HostKeys/`
- `Email/`
- `BuildExpiry/`

In Beekeeper:

- `HiveList/`
- `Pairing/`
- `ServerEditing/`
- `JobProgress/`
- `JobLog/`
- `Devices/`
- `RecoveryKey/`
- `Restore/`

Within a feature area, prefer small named objects such as:

- `Workflow`
- `Coordinator`
- `Navigator`
- `Store`
- `Factory`
- `Resolver`
- `Builder`
- `Runner`, for a wrapper around a child process such as `ssh`, `rsync` or a database dump

These names should describe a real role in the feature, not just wrap displaced code.

## What To Avoid

Avoid creating or growing broad cross-cutting buckets such as:

- `Services/`
- `Managers/`
- `Helpers/`
- `Utilities/`

Avoid extracting code just to deduplicate incidental duplication. Shared abstractions should be introduced carefully and only when the shared concept is real.

## Shared Code Rule

`Shared/` is a high bar, not a default destination.

Only move something into `Shared/` when:

- at least two distinct flows clearly depend on it
- the concept remains coherent outside its original feature
- the move improves clarity more than it increases indirection

## HiveKit

HiveKit holds the API types and the client that Beekeeper uses to talk to Hive. Nothing else goes there. Don't move daemon logic into HiveKit because two targets could import it; HiveKit is the wire contract, not a `Shared/` folder for the whole project.

## Refactor Heuristics

When changing code:

1. Move related files closer together first.
2. Extract small feature-local collaborators second.
3. Reevaluate whether any higher-level abstraction is actually necessary.

When touching a large file:

- prefer carving out focused, named collaborators
- keep those collaborators in the same feature directory by default
- stop extracting when the top-level object becomes a clear composer rather than a god object

## Reference Example

No feature has been named as the reference example yet. Once one clearly shows the desired direction, name it here. It should have:

- thin top-level view composition
- feature-local workflows and coordinators
- nearby state and supporting objects
- user-behavior-driven names
