#!/usr/bin/env bash
# Create the GitHub "release" environment that holds the signing secrets, and
# optionally store those secrets in it.
#
# Usage: scripts/setup-release-environment.sh [--repo owner/name] [--placeholders]
#
# It first runs scripts/protect-release-tags.sh, so only repository admins
# can push v* tags. The environment only accepts runs for tags matching v*,
# so the signing secrets reach release builds only. A workflow edited on a
# branch or in a pull request cannot read them. Running this again is safe.
#
# Run from a terminal, the script then asks for each secret and stores it
# with `gh secret set`, which reads the value without echoing it. Without a
# terminal (for example when a coding agent runs it), it only creates the
# environment and prints the commands for a person to run: agents should
# never handle signing keys.
#
# --placeholders creates any missing secret with an empty value, so the names
# are in place for a person to fill in (on GitHub or with `gh secret set`).
# Empty secrets count as missing. With all five empty, releases are ad hoc;
# with only some filled in, releases fail until all five are.
#
# Needs an authenticated `gh` with admin rights on the repository.
set -euo pipefail

REPO=""
PLACEHOLDERS=false
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="${2:?--repo needs owner/name}"; shift ;;
        --placeholders) PLACEHOLDERS=true ;;
        -h|--help) sed -n '2,22s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 1 ;;
    esac
    shift
done
[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

ENV=release
TAG_PATTERN='v*'
SECRETS=(MACOS_CERTIFICATE MACOS_CERTIFICATE_PASSWORD NOTARY_API_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID)

echo "Repository: $REPO"

# 0. Release tags: a v* tag reaches the secrets, so only admins may push one.
"$(dirname "$0")/protect-release-tags.sh" --repo "$REPO"

# 1. The environment, limited to the deployment rules added below.
gh api -X PUT "repos/$REPO/environments/$ENV" --silent --input - <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF

# 2. Allow only release tags.
policies="$(gh api "repos/$REPO/environments/$ENV/deployment-branch-policies" \
    --jq '.branch_policies[] | "\(.type) \(.name)"')"
if ! grep -qxF "tag $TAG_PATTERN" <<< "$policies"; then
    gh api -X POST "repos/$REPO/environments/$ENV/deployment-branch-policies" \
        -f name="$TAG_PATTERN" -f type=tag --silent
fi
policies="$(gh api "repos/$REPO/environments/$ENV/deployment-branch-policies" \
    --jq '.branch_policies[] | "\(.type) \(.name)"')"
others="$(grep -vxF "tag $TAG_PATTERN" <<< "$policies" || true)"
if [ -n "$others" ]; then
    echo "error: environment '$ENV' has deployment rules beyond 'tag $TAG_PATTERN'; refusing to configure signing secrets." >&2
    echo "Remove these rules from the repository's Settings > Environments > $ENV, then rerun this script:" >&2
    while IFS= read -r line; do echo "  $line" >&2; done <<< "$others"
    exit 1
fi
echo "Environment '$ENV' accepts runs for tags matching $TAG_PATTERN."

# 3. Secrets with the same names at repository level are readable by every
#    workflow run, which defeats the environment.
repo_level="$(gh secret list --repo "$REPO" --json name --jq '.[].name')"
for name in "${SECRETS[@]}"; do
    if grep -qxF "$name" <<< "$repo_level"; then
        echo "warning: $name is also a repository secret, readable by every run. Remove it with:" >&2
        echo "  gh secret delete $name --repo $REPO" >&2
    fi
done

# 4. The secrets themselves.
set_commands() {
    cat <<EOF
  base64 -i DeveloperID.p12 | gh secret set MACOS_CERTIFICATE --env $ENV --repo $REPO
  gh secret set MACOS_CERTIFICATE_PASSWORD --env $ENV --repo $REPO
  gh secret set NOTARY_API_KEY --env $ENV --repo $REPO < AuthKey_XXXXXXXXXX.p8
  gh secret set NOTARY_KEY_ID --env $ENV --repo $REPO
  gh secret set NOTARY_ISSUER_ID --env $ENV --repo $REPO
EOF
}

existing="$(gh secret list --env "$ENV" --repo "$REPO" --json name --jq '.[].name')"

if $PLACEHOLDERS; then
    for name in "${SECRETS[@]}"; do
        if ! grep -qxF "$name" <<< "$existing"; then
            printf '' | gh secret set "$name" --env "$ENV" --repo "$REPO"
            echo "Created $name with an empty value."
        fi
    done
    existing="$(gh secret list --env "$ENV" --repo "$REPO" --json name --jq '.[].name')"
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo
    echo "No terminal, so no secrets were set. A person should run these (README:"
    echo "\"Signing and notarization\" explains each value):"
    set_commands
    exit 0
fi

wanted() {
    # Ask whether to (re)set a secret. Returns 0 for yes.
    local name="$1" answer
    if grep -qxF "$name" <<< "$existing"; then
        read -r -p "$name is already set (it may be an empty placeholder). Replace it? [y/N] " answer
    else
        read -r -p "Set $name now? [Y/n] " answer
        answer="${answer:-y}"
    fi
    [[ "$answer" =~ ^[Yy] ]]
}
file_path() {
    local prompt="$1" path
    read -r -e -p "$prompt" path
    path="${path/#\~/$HOME}"
    [ -f "$path" ] || { echo "error: no file at $path" >&2; return 1; }
    printf '%s' "$path"
}

echo
echo "Signing secrets for '$ENV'. Press Enter to accept the default in [brackets]."
if wanted MACOS_CERTIFICATE; then
    p12="$(file_path "Path to your Developer ID Application .p12: ")"
    base64 -i "$p12" | gh secret set MACOS_CERTIFICATE --env "$ENV" --repo "$REPO"
fi
if wanted MACOS_CERTIFICATE_PASSWORD; then
    gh secret set MACOS_CERTIFICATE_PASSWORD --env "$ENV" --repo "$REPO"
fi
if wanted NOTARY_API_KEY; then
    p8="$(file_path "Path to your App Store Connect API key (AuthKey_*.p8): ")"
    gh secret set NOTARY_API_KEY --env "$ENV" --repo "$REPO" < "$p8"
fi
if wanted NOTARY_KEY_ID; then
    gh secret set NOTARY_KEY_ID --env "$ENV" --repo "$REPO"
fi
if wanted NOTARY_ISSUER_ID; then
    gh secret set NOTARY_ISSUER_ID --env "$ENV" --repo "$REPO"
fi

echo
echo "Secrets in '$ENV':"
gh secret list --env "$ENV" --repo "$REPO"
