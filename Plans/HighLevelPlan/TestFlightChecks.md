# Checks for TestFlight

What a simulator can't show and has to be tried on a real iPhone or iPad, in a TestFlight build. TestFlight builds are Release builds, so they also answer anything about the Secure Enclave, Face ID, the camera, local network access and Bonjour. The first TestFlight build comes from H1.

Add a check here whenever a slice leaves one, with the slice it came from. Check it off once it's been tried, and note anything that failed in the slice it belongs to.

- [x] **H1:** The TestFlight build installs on the iPhone and opens, with Beekeeper's icon on the Home Screen.
- [x] **H1:** The same on the iPad.
- [x] **H1:** TestFlight shows the project's version and the build number the release script printed, with no export compliance question.
- [x] **H1:** The first time Beekeeper reaches a Hive on the local network, iOS asks for local network access with Beekeeper's explanation. Allowing it lets the connection through, and turning it off in Settings › Privacy & Security › Local Network stops it. Possible once a device can pair (H2).
- [x] **H2:** On the iPad, Add a Hive › Scan the QR Code asks for camera access, scans the code Pair a Device shows on the Mac, and pairs.
- [x] **H2:** Live progress for a Run Now on the iPad moves as the run goes, and the run shows in the Job Log.
- [x] **H2:** Deleting a snapshot on the iPad asks for Face ID, then the snapshot leaves the list.
- [ ] **H2:** With Tailscale off on the iPad and the Hive's address options holding only its Tailscale name, Beekeeper still reaches the Hive over Wi-Fi through its Bonjour advertisement. Turning off Advertise on the Local Network in the Hive's settings stops that.
- [ ] **H2:** With the floating keyboard on the iPad, typing in a sheet or the Hive's settings leaves the sheet and window their full size. With the docked keyboard, the field being typed in stays above it. The sidebar never moves for either.
