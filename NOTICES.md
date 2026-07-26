# Third-party notices

perch is MIT licensed (see [LICENSE](LICENSE)). It bundles the following:

## mediaremote-adapter

- https://github.com/ungive/mediaremote-adapter
- Copyright (c) 2025, Jonas van den Berg and contributors
- BSD 3-Clause License — full text at
  [`Vendor/mediaremote-adapter/LICENSE`](Vendor/mediaremote-adapter/LICENSE)
- Vendored at v0.7.6; see
  [`Vendor/mediaremote-adapter/VENDORED.md`](Vendor/mediaremote-adapter/VENDORED.md)

Sources are vendored and built into `MediaRemoteAdapter.framework`, which ships inside
`perch.app`, alongside `mediaremote-adapter.pl`. It is what lets perch read now-playing
information on macOS 15.4 and later, where `MediaRemote` became entitlement-gated.
