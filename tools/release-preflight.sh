#!/usr/bin/env bash
#
# release-preflight — everything that must be true before a release starts.
#
# Separate from the release itself because these are the questions with yes/no answers, and a
# release that fails halfway through is worse than one that never started: by then a version has
# been bumped, possibly pushed, and the repository disagrees with itself about what is released.
#
# Prints one line per check and exits non-zero if any of them failed.

set -uo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-perch}"
failures=0

ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf '  note  %s\n' "$1"; }

echo "PREFLIGHT"

# --- the repository ----------------------------------------------------------------------------

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = "main" ]; then
    ok "on main"
else
    fail "on '$branch', not main — releases are cut from main"
fi

if [ -z "$(git status --porcelain)" ]; then
    ok "working tree is clean"
else
    fail "working tree has uncommitted changes — they would not be in the release"
fi

git fetch --quiet origin 2>/dev/null || true
local_head=$(git rev-parse HEAD)
remote_head=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
if [ "$local_head" = "$remote_head" ]; then
    ok "in sync with origin/main"
else
    fail "main and origin/main disagree — pull or push first"
fi

# Something to release. Cutting a version identical to the last one produces a release whose only
# difference from its predecessor is the number on it.
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$last_tag" ]; then
    ok "no previous tag — this would be the first release"
else
    count=$(git rev-list "$last_tag..HEAD" --count)
    if [ "$count" -gt 0 ]; then
        ok "$count commit(s) since $last_tag"
    else
        fail "no commits since $last_tag — nothing to release"
    fi
fi

# --- what CI thinks ----------------------------------------------------------------------------
#
# Local tests passing says the code is good on this machine. This says it is good on a clean one,
# which is the claim a downloadable build makes.

if repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
    checks=$(gh api "repos/$repo/commits/$local_head/check-runs" \
        --jq '.check_runs[] | "\(.status):\(.conclusion)"' 2>/dev/null || echo "")

    if [ -z "$checks" ]; then
        fail "no CI runs found for $(git rev-parse --short HEAD) — has it been pushed?"
    elif echo "$checks" | grep -qv '^completed:success$'; then
        fail "CI is not green on $(git rev-parse --short HEAD): $(echo "$checks" | tr '\n' ' ')"
    else
        ok "CI is green on $(git rev-parse --short HEAD)"
    fi
else
    fail "could not reach GitHub — gh not authenticated?"
fi

# --- what Apple needs --------------------------------------------------------------------------
#
# Only for a local `make release`. Releases normally come from release.yml, which signs on a runner
# with the `release` environment's secrets and needs nothing on this machine — so a laptop without
# a certificate is no longer a reason to refuse to release. These stay as checks rather than being
# dropped because when you *are* building locally, both otherwise fail at the end of a long build,
# after notarisation has already been waited on: the most expensive moment to find out.
#
# LOCAL=1 makes them hard failures again, for anyone deliberately cutting a release by hand.

credential_note() {
    if [ "${LOCAL:-0}" = "1" ]; then fail "$1"; else warn "$1 (fine — release.yml signs in CI)"; fi
}

if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    ok "Developer ID Application certificate present"
else
    credential_note "no Developer ID Application certificate — see docs/releasing.md"
fi

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    ok "notary profile '$NOTARY_PROFILE' works"
else
    credential_note "notary profile '$NOTARY_PROFILE' missing or rejected — see docs/releasing.md"
fi

# --- the code ----------------------------------------------------------------------------------

if make check >/tmp/perch-preflight-check.log 2>&1; then
    ok "make check"
else
    fail "make check failed — see /tmp/perch-preflight-check.log"
fi

echo
if [ "$failures" -gt 0 ]; then
    echo "preflight FAILED — $failures check(s). Nothing has been changed."
    exit 1
fi

echo "preflight passed — safe to release"
