# rsync

Hive bundles rsync 3.x inside `Hive.app`, as a separate program, for its exit codes and `--fake-super` (Plans/HighLevelPlan/00-Info.md §11). macOS's own `openrsync` has neither.

- **Source:** <https://download.samba.org/pub/rsync/src/>, at the version `Scripts/build-rsync.sh` names. The script checks the download against a SHA-256 taken from a tarball whose OpenPGP signature verified against the release key listed at <https://rsync.samba.org/download.html>.
- **Built by:** `Scripts/build-rsync.sh`, unmodified, for Apple silicon and Intel, with extended attribute support and without the optional libraries (OpenSSL, xxHash, zstd, LZ4, iconv, IDN).
- **License:** GNU General Public License version 3, with the exception for OpenSSL and xxHash, in [COPYING](COPYING). `Hive.app` carries a copy in `Contents/Resources/rsync/COPYING`.
