#!/usr/bin/env bash
# Enable Sparkle only when the maintainer supplies their public update key.
# Run after stamp-build-info.sh so forks use their own GitHub releases.
set -euo pipefail
PLIST="${1:?usage: configure-updates.sh Info.plist}"
KEY="${SPARKLE_PUBLIC_KEY:-}"
BUDDY=/usr/libexec/PlistBuddy
for name in SUPublicEDKey SUFeedURL SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
    "$BUDDY" -c "Delete :$name" "$PLIST" 2>/dev/null || true
done
[ -n "$KEY" ] || exit 0

fail() { echo "error: $*" >&2; exit 1; }
[[ "$KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail 'SPARKLE_PUBLIC_KEY must be a base64 Ed25519 public key.'
[ "$(printf '%s' "$KEY" | base64 --decode | wc -c | tr -d ' ')" = 32 ] || fail 'SPARKLE_PUBLIC_KEY must decode to 32 bytes.'
SOURCE="$("$BUDDY" -c 'Print :PullbarSourceRepository' "$PLIST")"
[[ "$SOURCE" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Updates require a GitHub source repository.'
"$BUDDY" -c "Add :SUPublicEDKey string $KEY" "$PLIST"
"$BUDDY" -c "Add :SUFeedURL string $SOURCE/releases/latest/download/appcast.xml" "$PLIST"
"$BUDDY" -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$PLIST"
"$BUDDY" -c 'Add :SURequireSignedFeed bool true' "$PLIST"
