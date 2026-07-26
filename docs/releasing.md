# Releasing

Gatekeeper needs three things beyond a working build: a **Developer ID signature**, the
**hardened runtime**, and a **stapled notarisation ticket**. Miss any one and a downloaded copy
refuses to open, however it was built.

## One-time setup

### 1. A paid membership

Developer ID certificates require the **Apple Developer Program** ($99/yr). A free Apple ID gives
you an account but not these certificates — which is the usual reason this stalls.

### 2. A Developer ID Application certificate

Easiest through Xcode:

> **Xcode → Settings → Accounts → your Apple ID → Manage Certificates → `+` → Developer ID
> Application**

If that item is missing or greyed out, the membership is not active.

Confirm it landed:

```sh
security find-identity -v -p codesigning
# should list: "Developer ID Application: Your Name (TEAMID)"
```

### 3. Notary credentials

Notarisation needs an **app-specific password**, not your Apple ID password. Create one at
[appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.

```sh
xcrun notarytool store-credentials perch \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password abcd-efgh-ijkl-mnop
```

That stores it in the keychain under the profile name `perch`, which the Makefile expects. The
password never appears in the repo or in a command you would paste into an issue.

## Cutting a release

```sh
make release
```

Which is: build → sign nested code then the bundle → zip → submit → wait → staple → re-zip →
verify. The artefact is `build/dist/perch-<version>.zip`.

Nested code is signed **before** the bundle. A signature covers what is inside it, so signing the
app before its framework invalidates the app's own seal.

The zip uses `ditto`, not `zip`: frameworks contain symlinks and extended attributes that `zip`
discards, and a notarisation submitted from a mangled archive fails in confusing ways.

## Verifying

```sh
make verify-release
```

`codesign --verify` and `spctl --assess` answer different questions. The first says the signature
is internally valid; the second says whether the system would actually let it run. Only the second
is the one users experience, so check both.

A stapled ticket matters because without it Gatekeeper has to reach Apple to check — so a first
launch on a machine that is offline fails.

## After the first notarised build, check media still works

perch reads now-playing by having `/usr/bin/perl` load a bundled framework. Perl is a platform
binary, and the hardened runtime changes the rules about what a process may load. The current
build signs that framework ad-hoc and works; a Developer ID signature *should* be equivalent, but
it is not obvious, and it is exactly the sort of thing that fails only in a distributed build.

```sh
make ui-probe    # the media scenario exercises the whole path
```

If media breaks only after notarisation, the framework's signature is where to look first.

## Version numbers

`VERSION` lives at the top of the `Makefile` and flows into `Info.plist`. Bump it before
releasing; `perch --version` reports it.

## Homebrew cask

Once a notarised zip is attached to a GitHub release and the repository is public:

```ruby
cask "perch" do
  version "0.1.0"
  sha256 "..."
  url "https://github.com/calvinlaughlin/perch/releases/download/v#{version}/perch-#{version}.zip"
  name "perch"
  desc "Minimal, config-driven macOS notch app"
  homepage "https://github.com/calvinlaughlin/perch"
  depends_on macos: ">= :sonoma"
  app "perch.app"
  zap trash: [
    "~/.config/perch",
    "~/Library/Preferences/dev.perch.perch.plist",
  ]
end
```

A cask can ship an un-notarised app, but every user then meets a Gatekeeper warning, so notarise
first.
