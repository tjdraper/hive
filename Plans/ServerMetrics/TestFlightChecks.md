# Checks for TestFlight

What a simulator can't show for server metrics and has to be tried on a real iPhone or iPad, in a TestFlight build over the tailnet. A simulator has no Secure Enclave, so it can't sign in to a Hive and shows these pages only with made-up figures. The backups plan's checks are in [Plans/HighLevelPlan/TestFlightChecks.md](../HighLevelPlan/TestFlightChecks.md).

Add a check here whenever a slice leaves one, with the slice it came from. Check it off once it's been tried, and note anything that failed in the slice it belongs to.

## iPhone

- [ ] **B9:** A Hive's page has a Metrics row above Job Log, opening the dashboard as a list: stopped servers first, each row's state as an icon and a word, and its CPU, memory, swap and fullest disk. The figures move with each sample.
- [ ] **B9:** Tapping a server opens its page, and Back returns to the dashboard. Show Metrics on a server's page opens the same page, and Back returns to the server.
- [ ] **B9:** A server's page shows one chart at a time. Swiping, and the charts menu in the toolbar, move between them. The range (1H to 1Y) and a chosen moment stay as they are on every chart.
- [ ] **B9:** Tapping a chart opens the processes at that moment in a sheet, half the screen high, with the chart still above it. Tapping the chart again while the sheet is open moves the moment. Touching and holding moves a dashed rule along the chart, with the legend reading the figures under it, and lifting the finger chooses that moment. A plain swipe still scrolls and pages.
- [ ] **B9:** In the sheet, Processes, Containers and Services each list the moment's busiest, in CPU or memory order.
- [ ] **B9:** Processes, a filesystem, and Containers and Services each open from the links beside a chart's title. Each shows its charts one at a time above a list, and Show Live returns to live figures after a moment's chosen.
- [ ] **B9:** On Containers and Services, tapping a group opens its processes in a sheet. By Service and Each Container both list, and an unnamed container shows its short ID and what it runs.
- [ ] **B9:** Every page reads well in light and dark, and with larger text in Settings › Display & Brightness.
- [ ] **C1:** A dashboard row with an alert shows it in a line under the server's name, with a triangle beside the figure it's about. Change Alert Limits… on a server's page opens the limits as a sheet, with number keyboards, and Save and Cancel in its bar.
- [ ] **C2:** The Hive Mac's row is named after the Hive, with a Mac's icon and a "Hive Mac" tag. Tapping it opens its page, and Back returns to the dashboard. Its CPU chart has only user and system, its moment sheet lists processes with no Containers or Services choice, and other users' processes show as one row with "—" for memory.

## iPad

- [ ] **B9:** The Metrics sidebar row shows the dashboard's cards. A server's page shows its charts in two columns at full width, and one column with the sidebar showing or in Split View, with the range in the toolbar.
- [ ] **B9:** Tapping a chart opens the processes in the inspector beside the charts. Touching and holding moves the moment along a chart.
- [ ] **B9:** Containers and Services shows its table, and selecting a group shows its processes beside it.

## Both

- [ ] **C2:** Turning off Read the Hive Mac's Metrics in the Hive's settings takes the Hive Mac off the dashboard, and turning it back on brings it back.

- [ ] **B9:** With a server's page open, leaving Beekeeper for a few minutes and coming back shows the figures from while it was away at once, the dashboard's cards move with samples again within seconds, and Run Now's progress on a job still moves.
