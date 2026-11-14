# H2. Beekeeper on iPad

**Phase H — iPhone and iPad** · Mixed, 1–2 sessions, TestFlight

References like §15 point to [00-Info.md](00-Info.md).

## Engine

- **Bonjour** (§15): Hive advertises itself on every LAN interface it listens on, never on `127.0.0.1` or the tailnet, with a setting to turn it off. Beekeeper finds advertised Hives and fills in their address.
- **Secure Enclave keys on iPhone and iPad,** for signing in and for confirmed actions with Face ID or Touch ID (§6), kept where only Beekeeper can use them (B2)
- **The recovery file** kept on each device (F2)
- **Scanning the pairing QR code** with the camera, beside pasting the code (G1)

## UI

Built with you:

- **The Mac's layout, adapted for iPad,** with sheets where the Mac uses windows, and several Hives connected at once

**Done when:** on your iPad through TestFlight, Beekeeper pairs by scanning the QR code, shows live progress for a run, and deletes a snapshot on the test drive after Face ID or Touch ID; and the checks are added to [TestFlightChecks.md](TestFlightChecks.md).

## Decisions

- **Hive advertises one registration per interface,** through `dns_sd`, on each local network it listens on: multicast interfaces that are neither loopback nor point-to-point. Tailscale's `utun` is multicast-capable, so registering on every interface at once would include it. The advertisement is the Hive's name, with its ID in the TXT record (`hive=<ID>`). It follows the listeners, so it changes within a few seconds of an address appearing, the settings changing, or a rename.
- **The setting** is Advertise on the Local Network, on by default, in `HiveSettings.advertisesOnLocalNetwork`. It's recorded in the audit log and kept in recovery files. A Hive or Beekeeper from before it reads it as on, so the API version didn't change.
- **Beekeeper browses only once it has a Hive that isn't on its own Mac, or while Add a Hive is open,** so a Mac that only manages its own Hive is never asked for local network access.
- **A found address is tried before the Hive's own,** for sign-in and for pairing with a code, and isn't saved. Anything on the network can advertise any Hive ID, so another key at a found address counts as the Hive not being there, never as its identity changing.
- **The found address is the Bonjour host name,** such as `Karrin.local`, which resolves only on the local network.
- **Scanning uses VisionKit's `DataScannerViewController`,** and pairs as soon as it reads a whole code.
- **Face ID prompts** read "Allow Beekeeper to …", since iOS shows the reason as it is, where macOS puts "Beekeeper is trying to" before it.
- **Sheets keep their fixed sizes on the Mac only** (`macSheetSize`). iPadOS sizes its own.
- **Sheets lay out their buttons through `SheetLayout`:** on the Mac in a bar along the bottom, and on iPad in the navigation bar, Cancel at the leading edge and the confirming button at the trailing, with anything else, such as Back or a failure, in a bar along the bottom that only shows when there's something in it.
- **Text fields have their labels above them** (`StackedRow`), as in Locus Calendar and Locus ToDo. Controls, such as a number with a stepper, keep the label at the side.
- **Group boxes take the Mac's look on iPad** (`LabelAboveGroupBoxStyle`): the label above a softly filled box, rather than iOS's card with the label inside it.
- **On iPad the sidebar is plain rows** (`SidebarOutline`), the rows under a Hive or server indented, with the row drawing its own arrow. iPadOS doesn't keep a `DisclosureGroup` label highlighted: the highlight goes when a sheet closes, and a selection made in code never shows. The Mac keeps its native outline.
- **A `Label` is never a form row's value on iPad.** As the value of a `LabeledContent` in a form, one leaves the row hundreds of points tall, so those rows use an `HStack` of the icon and text.
- **Sheets opened from inside a form open from outside it** (`hostsFormSheets()`). On iPad, a sheet attached to a form's section could close a moment after it first opened.
- **The path in the toolbar fits itself on iPad:** the whole path when it leaves room for the page's buttons, and otherwise only its icons, with the page's name beneath. The room is the detail's width less 200 points for the page's buttons and the toolbar's margins, and 130 more for the window's controls while the sidebar is hidden, both measured on iPadOS 26. Server and job pages hide iPadOS's inline title, which repeated the path's last part. The Hive page keeps it, since removing it takes the tabs with it.
- **The sidebar ignores the keyboard,** as Locus Calendar's main window does, since nothing in it takes typing. Sheets and pages needed nothing for the floating keyboard once their forms filled them.
- **The sidebar is at least 280 points wide on iPad,** and a Hive's status gives way to its dot alone before its name is cut short.
