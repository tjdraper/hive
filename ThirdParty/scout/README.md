# Scout's static Linux runtime

`hive-scout` for Linux is built with Swift's Static Linux SDK (`Scripts/build-scout.sh`), which links into it the parts of the SDK below as well as Swift's runtime, standard library and Foundation, and LLVM's libunwind and libc++abi. Those last are under the Apache License 2.0 with the Runtime Library and LLVM exceptions, which ask for no notice in a binary. `Hive.app` carries the binaries, so its third-party notices (`Scripts/write-third-party-notices.sh`) include these licenses.

- **musl,** the C library: MIT, in [musl-COPYRIGHT](musl-COPYRIGHT), from <https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT?h=v1.2.5>.
- **mimalloc,** the memory allocator: MIT, in [mimalloc-LICENSE](mimalloc-LICENSE), from <https://github.com/microsoft/mimalloc/blob/v2.2.4/LICENSE>.

The versions are the SDK's, listed in its `sbom.spdx.json`. Check these files again when `Scripts/build-scout.sh` moves to a new SDK.
