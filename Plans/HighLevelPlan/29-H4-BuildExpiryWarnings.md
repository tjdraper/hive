# H4. Build expiry warnings

**Phase H — iPhone and iPad** · Engine, 1 session, TestFlight

References like §16 point to [00-Info.md](00-Info.md). Read the brainstorm's "Warnings before an iOS build expires".

- **Beekeeper works out how it was distributed and when it expires** (§16): ad hoc from `embedded.mobileprovision`, TestFlight from the stamped build date, Developer ID with no expiry
- **Build details at sign-in:** platform, device name, version, build, how it was distributed and when it expires, stored for each device
- **Hive checks once a day** and emails 14 and 3 days before, once per build. A new build resets the warnings.
- **The device list** shows each device's build and expiry, and marks expired ones
- **The setting to turn warnings off** for each Hive

- **From E2:** alerts live in `HiveCore/Alerts/`. A warning is a notice: add an `AlertFacts` case whose `key` names the device, build and warning, so it's sent once and a restart can't send it twice, open it with `AlertStore.apply([.open(...)], at:)`, and write its email in `AlertMessageBuilder`. `AlertMailer` sends it with the rest. The daily check can run from `AlertMonitor.check()`.

## Tests

- Reading `ExpirationDate` from a sample provisioning profile
- Each warning goes out once per build, and a new build resets them
- Turning the setting off sends nothing

**Done when:** a TestFlight build on your iPhone reports its expiry and Hive's device list shows it; and the tests pass.

## Decisions

- **The device's name isn't reported again at sign-in.** Hive already has the name it paired with, and iOS only gives an app "iPhone" or "iPad" without a special entitlement.
- **Builds installed from Xcode are warned about too,** from their provisioning profile's expiry, which is 7 days for a free Apple account. A profile that allows debugging (`get-task-allow`) is a development build, and one that doesn't is ad hoc. Mac builds report no expiry, and simulator builds report themselves as development builds, since they have no profile and would otherwise look like TestFlight's.
- **Reading the profile is in HiveKit** (`BuildExpiryResolver`), beside the build it shapes, since Beekeeper has no test target. The profile is a CMS signed message that iOS can't open, so the property list is cut out from inside it. The test profile is signed with a throwaway certificate and holds made-up values.
- **The warning sent is recorded on the device** (`buildWarning`), in the same transaction that opens it, so a restart can't send it twice. Reporting a different build clears it. A sign-in that reports no build clears the stored one, since it no longer says what the device runs.
- **A build Hive can't read is left out, and the sign-in goes ahead,** such as one from a platform added later or with a version Hive won't store. Beekeeper reads the device list the same way.
- **Checked with the other alerts each minute,** rather than once a day, since it only reads the device list. A build first reported with under 3 days left gets only the last warning, and an expired one gets none.
- **The setting is in the Hive's Settings, below Email,** and saves as soon as it's changed, keeping any changes above it that wait for Save. It's audited, and carried in recovery files.
- **The device list** has Beekeeper and Expires columns, with an expiry within 14 days in orange and an expired one in red. On iPhone the table shows only its first column, so both go under the name.
