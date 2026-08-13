---
name: release
description: Cut a signed, notarised perch release — preflight, version bump, build, notarise, tag, publish, and the Homebrew cask. Use when the user says /release, or asks to cut, ship, or publish a release.
---

# Releasing perch

One command from a green main to something a stranger can download and open.

**Arguments.** `/release` picks the version itself. `/release 0.3.0` pins it. `/release patch` or
`/release minor` forces the kind of bump.

**You stop exactly once**, after the notarised build exists and before anything is public. Every
step before that is reversible without anyone seeing it; every step after is not.

## 1. Preflight — before touching anything

```sh
make release-preflight
```

Checks: on main, clean tree, in sync with origin, commits exist since the last tag, CI green on
HEAD, Developer ID certificate present, notary profile usable, `make check` passes.

**If it fails, stop and report.** Do not fix and continue silently — a failed preflight usually
means the user thinks the repository is in a state it is not, and that is worth their attention
before a version number gets attached to it. Nothing has been changed at this point.

## 2. Choose the version

Read `VERSION` in the `Makefile` and the last tag. Then read what has landed since:

```sh
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

**Minor** (`0.2.0` → `0.3.0`) if there are new features, changed defaults, or changed behaviour —
including behaviour someone on the previous version would notice. **Patch** (`0.2.0` → `0.2.1`)
only if it is fixes alone.

Pre-1.0, the minor number carries features and breaks; the patch number is for fixes. Getting this
wrong has a specific cost: someone on the old version reasonably skips a patch release, then finds
their notch behaves differently.

State the version and the one-line reason in your final report. Do not ask about it separately —
it arrives at the single stop below with everything else.

## 3. Bump, via a pull request

Edit `VERSION` in the `Makefile`. **main is protected** — it requires a pull request and a green
`Check`, so the bump cannot be pushed directly however small it is:

```sh
git checkout -b release-<version>
git commit -am "Release <version>"
git push -u origin release-<version>
gh pr create --title "Release <version>" --body "…"
```

Wait for CI, then merge and return to main:

```sh
gh pr checks <n> --watch --fail-fast
gh pr merge <n> --squash --delete-branch
git checkout main && git pull
```

**Abort if CI goes red.** Nothing is public yet; a red build is a reason to stop, not to retry.

## 4. Build, sign, notarise — usually not yours to do

`release.yml` does this on a runner when a `v*` tag is pushed, and that is the normal path: it
checks the tag against `VERSION` and CI against the commit, signs, notarises, verifies, and
publishes. **So step 7 is the whole of the release** and there is nothing to build here.

Build locally only if the workflow is unavailable — no `release` environment secrets, a runner
outage, or the user asks for it. Then:

```sh
make release
```

Build → sign nested code then the bundle → zip with `ditto` → submit → wait → staple → re-zip →
verify. Several minutes, most of it Apple's side.

Keep the tail of the output. The four things that must be true, and they are the report's evidence:

- notarisation `status: Accepted`
- `stapled ticket: The validate action worked!`
- `gatekeeper: accepted` with `source=Notarized Developer ID`
- `build/perch.app/Contents/MacOS/perch --version` prints the new version

If notarisation is **rejected**, stop. `xcrun notarytool log <submission-id> --keychain-profile perch`
says why. The version bump is already on main, which is fine — it is released when it is tagged,
not when it is numbered.

## 5. Draft the notes

From `git log <last-tag>..HEAD`, grouped **New** / **Changed** / **Fixed**. Written for someone
upgrading, not for someone reading the diff:

- Say what a feature *does*, not which PR added it.
- **Call out anything that changes behaviour they already rely on**, including changed defaults.
  This is the part release notes exist for.
- If something looks breaking but is not, say so — a widget that never shipped cannot be lost.
- End with the compare link: `https://github.com/calvinlaughlin/perch/compare/<last-tag>...v<version>`

## 6. Stop — the single confirmation

Show the user, in one message: the version and why, the evidence gathered so far, and the full
notes. Ask whether to publish.

Nothing so far is visible to anyone but them. Pushing the tag is what starts a signed build and a
public release, and it cannot be taken back once the cask has moved.

## 7. Publish — push the tag

```sh
git tag -a v<version> -m "perch <version>"
git push origin v<version>
```

That is the whole of it. `release.yml` builds, signs, notarises, verifies and publishes; the
`release` environment may hold the run for a reviewer first. Watch it, and **read the failure
rather than retrying** — a signing or notarisation failure means the artefact is wrong, not that
the run was unlucky:

```sh
gh run watch $(gh run list --workflow Release --limit 1 --json databaseId -q '.[0].databaseId') --exit-status
```

If a tag has to be withdrawn before the release published, `git push --delete origin v<version>`
and delete it locally. Once the release exists and the cask has moved, go forward with a new
version instead.

If you built locally at step 4 because the workflow was unavailable, publish that artefact by hand
instead:

```sh
gh release create v<version> build/dist/perch-<version>.zip \
  --title "perch <version>" --notes "<the notes>"
```

## 8. The Homebrew cask

`.github/workflows/bump-cask.yml` does this automatically when the release is published. Give it a
moment, then confirm it actually ran and landed:

```sh
gh run list --workflow bump-cask.yml --limit 1
brew update >/dev/null && brew info --cask calvinlaughlin/tap/perch | head -3
```

If the workflow was skipped — no `TAP_TOKEN` secret — or failed, fall back to doing it here:

```sh
make tap
```

Either way, **verify the result the way a user meets it**, not by reading the file:

```sh
brew fetch --cask calvinlaughlin/tap/perch
```

That resolves the cask from the published tap and checksums the real download. A cask edit is not
evidence that installing works.

## 9. Report, and say what is still unchecked

Give the release URL, the version, and what was verified with the evidence for it.

Then two things, plainly:

- **`make ui-probe FULL=1` has not run.** `docs/releasing.md` asks for it after a notarised build
  for a specific reason: perch reads now-playing by having `/usr/bin/perl` load a bundled
  framework, and the hardened runtime governs what a process may load. It is the one failure mode
  unique to a distributed build. It needs a notched display, Accessibility permission, and about a
  minute of the pointer, so it cannot be run without the user being away from the keyboard — offer
  it rather than assume.
- **`make install`** replaces `/Applications/perch.app` with the notarised bundle, without
  rebuilding, so the signature and ticket survive. Offer it; do not do it unasked.

## Rules

- **Never report a step as verified without the command output that shows it.** Every claim in the
  final report traces to something in this session's transcript. "Notarised" means `Accepted`
  appeared in a log you read — in the workflow run when CI built it, locally otherwise — not that
  a command exited zero.
- **Never skip preflight**, including on a re-run after a failure partway through.
- If a tag for the version already exists, stop — that version is published; pick the next one.
- Do not create the GitHub release before the tag is pushed; a release without its tag is a dangling
  artefact people can download and not reproduce.
