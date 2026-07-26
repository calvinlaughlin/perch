# Vendored dependency

[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg,
BSD 3-Clause. See [LICENSE](LICENSE).

- version: **v0.7.6**
- commit: `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`

## Why perch needs it

macOS 15.4 added entitlement checks to `mediaremoted`. Third-party apps calling
`MRMediaRemoteGetNowPlayingInfo` now get nothing back. This adapter works around that:
`/usr/bin/perl` carries the bundle identifier `com.apple.perl5`, which *is* entitled, so a
helper framework is loaded by Perl and streams now-playing JSON on stdout.

perch therefore reads media state from a subprocess rather than a framework call, and
`MediaSource` exists so that the day Apple closes this loophole, only one implementation changes.

## Why it is built with clang rather than CMake

Upstream builds with CMake. perch builds the same sources with a direct clang invocation from its
own Makefile (see the `adapter` target) so that a clone builds with `make` and nothing else — no
Homebrew, no CMake. `src/test/main.m` is not vendored — it defines a standalone `main()` that cannot go in a dylib —
but the rest of `src/test` is, because `src/adapter/test.m` needs its headers.

## Updating

Re-clone at the new tag, copy `bin`, `include`, `src`, `LICENSE`, `README.md`,
`CMakeLists.txt`, delete `src/test/main.m`, and update the version and commit above. Check whether
`CMakeLists.txt`'s source list changed — the Makefile compiles `src/**/*.m` wholesale, so new
files are picked up, but new link-time framework dependencies are not.
