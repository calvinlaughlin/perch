#!/usr/bin/env bash
#
# update-tap — point the Homebrew cask at a published release.
#
# Scripted rather than done by hand because the checksum is the part that matters and the part
# easiest to get subtly wrong: it must be of the asset **as published**, not of the local zip the
# release was built from. Those are usually identical, and when they are not, every `brew install`
# fails with a checksum mismatch and no clue why.
#
# Usage:  tools/update-tap.sh 0.2.0

set -euo pipefail

version="${1:-}"
[ -n "$version" ] || { echo "usage: tools/update-tap.sh <version>" >&2; exit 2; }

TAP_REPO="${TAP_REPO:-calvinlaughlin/homebrew-tap}"
CASK_PATH="${CASK_PATH:-Casks/perch.rb}"
ASSET_URL="https://github.com/calvinlaughlin/perch/releases/download/v${version}/perch-${version}.zip"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The published asset, fetched the way a user's brew would fetch it.
echo "fetching $ASSET_URL"
http=$(curl -sL -w '%{http_code}' -o "$work/asset.zip" "$ASSET_URL")
[ "$http" = "200" ] || { echo "error: asset returned HTTP $http — is the release published?" >&2; exit 1; }

sha=$(shasum -a 256 "$work/asset.zip" | awk '{print $1}')
echo "sha256 $sha"

gh repo clone "$TAP_REPO" "$work/tap" -- --quiet
cask="$work/tap/$CASK_PATH"
[ -f "$cask" ] || { echo "error: no $CASK_PATH in $TAP_REPO" >&2; exit 1; }

# Anchored to the stanza names so this cannot rewrite a version string that happens to appear in a
# URL or a comment.
/usr/bin/sed -i '' \
    -e "s|^  version \".*\"|  version \"${version}\"|" \
    -e "s|^  sha256 \".*\"|  sha256 \"${sha}\"|" \
    "$cask"

grep -q "version \"${version}\"" "$cask" || { echo "error: version did not update" >&2; exit 1; }
grep -q "sha256 \"${sha}\"" "$cask" || { echo "error: sha256 did not update" >&2; exit 1; }

# Homebrew's own linter, so style problems surface here rather than in someone's install.
if command -v brew >/dev/null 2>&1; then
    (cd "$work/tap" && brew style "$CASK_PATH")
fi

if git -C "$work/tap" diff --quiet; then
    echo "cask already at $version — nothing to push"
    exit 0
fi

git -C "$work/tap" diff
git -C "$work/tap" add "$CASK_PATH"
git -C "$work/tap" commit --quiet -m "perch ${version}"
git -C "$work/tap" push --quiet

echo "pushed $TAP_REPO"

# What a user actually experiences: resolve the cask from the tap and check the download against
# the checksum just written. Editing the file is not evidence that installing works.
if command -v brew >/dev/null 2>&1; then
    tap_name=${TAP_REPO/homebrew-/}
    brew update --quiet >/dev/null 2>&1 || true
    brew info --cask "${tap_name}/perch" | head -3
    brew fetch --cask "${tap_name}/perch"
fi
