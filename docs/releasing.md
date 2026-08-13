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

Say **`/release`** to a coding agent. That runs `.claude/skills/release/SKILL.md`, which is this
document turned into a procedure: preflight, choose the version, bump, build, notarise, and then
stop — once, with the notarised artefact and the draft notes in front of you — before tagging and
publishing. Optionally `/release 0.3.0` to pin the version, or `/release patch`.

It stops in exactly one place because that is the last moment nothing is public. Everything before
it lives on your machine and in one commit; everything after is a tag, a release, and a cask other
people install from.

By hand, the same path:

```sh
make release-preflight     # on main, clean, synced, CI green, credentials present, make check
$EDITOR Makefile           # bump VERSION
make release               # sign, notarise, staple, verify
git tag -a v<version> -m "perch <version>" && git push origin v<version>
gh release create v<version> build/dist/perch-<version>.zip --title "perch <version>" --notes "…"
```

**Run the preflight before touching `VERSION`.** A release that fails halfway is worse than one
that never began: the version is already bumped, possibly pushed, and the repository disagrees with
itself about what has been released.

`make release` is: build → sign nested code then the bundle → zip → submit → wait → staple →
re-zip → verify. The artefact is `build/dist/perch-<version>.zip`.

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

### What CI checks after a release

Two workflows fire on `release: published`, and between them they check the things this machine
cannot. It already trusts the signing certificate, already has perch in `/Applications`, and has
run every intermediate build — so "it opens here" is compatible with a download nobody else can
open.

- **`bump-cask.yml`** points the Homebrew cask at the new release. It checksums the asset **as
  published** rather than the local zip it was built from; those are normally identical, and when
  they are not, every `brew install` fails on a mismatch with nothing to explain it.
- **`release-smoke-test.yml`** waits for the cask, then installs it on a clean `macos-15` runner
  and asserts the app is really there, that `spctl` reports `source=Notarized Developer ID`, and
  that the ticket is stapled. Then it uninstalls.

Neither can replace `make ui-probe` — no runner has a camera housing or an Accessibility grant.

### One-time: the tap token

`bump-cask.yml` needs to push to a different repository, so it needs a token of its own. Without
one it **skips** rather than fails, and `make tap` does the same job locally.

1. [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
   — a fine-grained token, **only** the `homebrew-tap` repository, **Contents: read and write**.
   Nothing else, so a leak cannot reach perch itself.
2. `gh secret set TAP_TOKEN --repo calvinlaughlin/perch` and paste it.

Check it took with `gh run list --workflow bump-cask.yml` after the next release: a skipped run
logs a warning saying so.

## Installing a release locally

`make install` deliberately does **not** rebuild. `make app` re-signs ad-hoc every time, so an
install that rebuilt would silently discard the Developer ID signature and notarisation ticket of
a bundle you had just released — and the result looks fine until someone else downloads it. It
reports what it installed:

```
installed to /Applications/perch.app — signed and notarised
```

## After the first notarised build, check media still works

perch reads now-playing by having `/usr/bin/perl` load a bundled framework. Perl is a platform
binary, and the hardened runtime changes the rules about what a process may load. The current
build signs that framework ad-hoc and works; a Developer ID signature *should* be equivalent, but
it is not obvious, and it is exactly the sort of thing that fails only in a distributed build.

```sh
make ui-probe    # the media scenario exercises the whole path
```

If media breaks only after notarisation, the framework's signature is where to look first.

**Result of the first run (v0.1.0):** it works. Every probe scenario passes on the notarised
bundle, so `/usr/bin/perl` loading a Developer ID–signed framework needs no entitlement.

## Version numbers

`VERSION` lives at the top of the `Makefile` and flows into `Info.plist`. Bump it before
releasing; `perch --version` reports it.

## Homebrew cask

Once a notarised zip is attached to a GitHub release and the repository is public:

```ruby
cask "perch" do
  version "0.2.0"
  sha256 "..."
  url "https://github.com/calvinlaughlin/perch/releases/download/v#{version}/perch-#{version}.zip"
  name "perch"
  desc "Minimal, config-driven notch app"
  homepage "https://github.com/calvinlaughlin/perch"
  depends_on macos: :sonoma
  app "perch.app"
  binary "#{appdir}/perch.app/Contents/MacOS/perch"
  zap trash: "~/.config/perch"
end
```

`shasum -a 256 build/dist/perch-<version>.zip` gives the checksum, and `brew style Casks/perch.rb`
checks the result.

Three things in there are easy to get wrong:

- **`binary` is not optional.** The app bundle's executable *is* the CLI — there is no second
  target — but a cask with only an `app` stanza installs no `perch` command, and the config file
  perch writes tells people to run `perch +show-config --default --docs`. Without this line that
  instruction is a dead end for everyone who installed via brew.


- **`depends_on macos: :sonoma` means Sonoma *or later*.** A bare symbol is a minimum in a cask —
  `Cask::DSL::DependsOn#macos=` parses it with a `>=` comparator — even though the same symbol in a
  *formula* means that version exactly. `brew info --cask` prints the resolved requirement
  (`Required: macOS >= 14`) if you want to see it rather than trust it. The string form
  `">= :sonoma"` reads as though it were the safer spelling; it is deprecated, and `brew style`
  will tell you to replace it with the bare symbol.
- **The description must not name the platform.** `brew style` rejects "macOS notch app" in `desc`,
  since every cask is macOS.

A cask can ship an un-notarised app, but every user then meets a Gatekeeper warning, so notarise
first.
