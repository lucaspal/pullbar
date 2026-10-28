#!/usr/bin/env bash
# Prepare a release: on a new release/<tag> branch, move the Unreleased notes
# in CHANGELOG.md into an entry for <tag>, add the pull requests merged since
# the previous tag, and commit.
#
# Usage: scripts/create-release.sh v1.2.3
#
# Run it on an up-to-date main with a clean working tree. Afterwards, push the
# branch, merge its pull request, and tag the merge commit on main; the tag
# starts the release pipeline. AGENTS.md describes every step.
#
# REPO (default lucaspal/Pullbar) is the GitHub repository for pull request
# lookups and release links. REMOTE (default origin) is the git remote that
# holds main and the tags.
set -euo pipefail

TAG="${1:?usage: scripts/create-release.sh vX.Y.Z}"
REPO="${REPO:-lucaspal/Pullbar}"
REMOTE="${REMOTE:-origin}"
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

printf '%s\n' "$TAG" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' ||
    fail "$TAG is not a semver tag like v1.2.3 or v1.2.3-rc.1."
[ -z "$(git status --porcelain)" ] || fail "the working tree has changes; commit or stash them first."

git fetch --quiet --tags "$REMOTE" main
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/main")" ] ||
    fail "HEAD is not $REMOTE/main. Run: git switch main && git pull $REMOTE main"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
    [ -n "$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG")" ]; then
    fail "tag $TAG already exists."
fi
if git ls-remote --exit-code --heads "$REMOTE" "release/$TAG" >/dev/null; then
    fail "branch release/$TAG already exists on $REMOTE."
fi

SUMMARY="$(mktemp)"
trap 'rm -f "$SUMMARY"' EXIT
REPO="$REPO" scripts/release-notes.sh --summary HEAD > "$SUMMARY"

git switch --quiet -c "release/$TAG"
scripts/changelog.sh release "${TAG#v}" "$REPO" "$SUMMARY"
git add CHANGELOG.md
git commit --quiet -m "Release $TAG"

echo "Prepared release/$TAG:"
echo
git show --stat --format='%s' HEAD | sed 's/^/  /'
echo
echo "Next steps:"
echo "  1. git push -u $REMOTE release/$TAG"
echo "  2. gh pr create --repo $REPO --base main --head release/$TAG --title 'Release $TAG' --fill"
echo "  3. Merge the pull request, then tag the merge commit on main:"
echo "       git switch main && git pull $REMOTE main"
echo "       git tag -a $TAG -m 'Release $TAG' && git push $REMOTE $TAG"
