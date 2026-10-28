#!/usr/bin/env bash
# Edit CHANGELOG.md.
#
# Usage:
#   scripts/changelog.sh release <version> <repo> <summary-file>
#       Move the Unreleased notes into a new version entry, add the pull
#       request list from <summary-file>.
#
# Called by scripts/create-release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

EMPTY='_Nothing yet._'

fail() { echo "error: $*" >&2; exit 1; }
usage() { sed -n '2,9s/^# \{0,1\}//p' "$0" >&2; exit 1; }

# Replace a file with the output of a command, only if the command succeeds.
rewrite() {
    local file="$1" tmp
    shift
    tmp="$(mktemp)"
    if "$@" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

new_release_entry() {
    local version="$1" repo="$2" summary="$3"
    awk -v version="$version" -v repo="$repo" -v date="$(date +%Y-%m-%d)" \
        -v summaryfile="$summary" -v empty="$EMPTY" '
        function emit(    i, first, last, summary, line) {
            first = 1; last = n
            while (first <= n && body[first] ~ /^[[:space:]]*$/) first++
            while (last >= first && body[last] ~ /^[[:space:]]*$/) last--
            if (first == last && body[first] == empty) first = last + 1

            summary = ""
            while ((getline line < summaryfile) > 0) summary = summary line "\n"
            if (summary == "") summary = "_None._\n"

            print "## Unreleased\n\n" empty "\n"
            print "## [" version "](https://github.com/" repo "/releases/tag/v" version ") - " date "\n"
            for (i = first; i <= last; i++) print body[i]
            if (first <= last) print ""
            printf "### Pull requests\n\n%s", summary
            emitted = 1
        }
        state == 0 && /^## / {
            if ($0 != "## Unreleased") { bad = 1; exit 1 }
            state = 1; next
        }
        state == 0 { print; next }
        state == 1 && /^## / { emit(); print ""; state = 2 }
        state == 1 { body[++n] = $0; next }
        { print }
        END {
            if (bad || state == 0) exit 1
            if (!emitted) emit()
        }
    ' CHANGELOG.md
}

case "${1:-}" in
    release)
        [ $# -eq 4 ] || usage
        rewrite CHANGELOG.md new_release_entry "$2" "$3" "$4" ||
            fail "CHANGELOG.md must start its entries with '## Unreleased'."
        ;;
    *)
        usage
        ;;
esac
