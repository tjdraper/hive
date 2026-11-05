# H4. Build expiry warnings

**Phase H — iPhone and iPad** · Engine, 1 session, TestFlight

References like §16 point to [00-Info.md](00-Info.md). Read the brainstorm's "Warnings before an iOS build expires".

- **Beekeeper works out how it was distributed and when it expires** (§16): ad hoc from `embedded.mobileprovision`, TestFlight from the stamped build date, Developer ID with no expiry
- **Build details at sign-in:** platform, device name, version, build, how it was distributed and when it expires, stored for each device
- **Hive checks once a day** and emails 14 and 3 days before, once per build. A new build resets the warnings.
- **The device list** shows each device's build and expiry, and marks expired ones
- **The setting to turn warnings off** for each Hive

## Tests

- Reading `ExpirationDate` from a sample provisioning profile
- Each warning goes out once per build, and a new build resets them
- Turning the setting off sends nothing

**Done when:** a TestFlight build on your iPhone reports its expiry and Hive's device list shows it; and the tests pass.
