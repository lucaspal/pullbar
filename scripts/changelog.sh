#!/usr/bin/env bash
# Edit CHANGELOG.md and the changelog block in README.md.
#
# Usage:
#   scripts/changelog.sh release <version> <repo> <summary-file>
#       Move the Unreleased notes into a new version entry, add the pull
#       request list from <summary-file>, then refresh the README.
#   scripts/changelog.sh readme
#       Copy the two newest CHANGELOG entries into README.md, between the
#       changelog:start and changelog:end markers.
#
# Called by scripts/create-release.sh; run `readme` by hand after editing the
# Unreleased notes.
set -euo pipefail
cd "$(dirname "$0")/.."

EMPTY='_Nothing yet._'
START='<!-- changelog:start -->'
END='<!-- changelog:end -->'

fail() { echo "error: $*" >&2; exit 1; }
usage() { sed -n '2,13s/^# \{0,1\}//p' "$0" >&2; exit 1; }

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

# Print the two newest CHANGELOG entries with every heading one level lower,
# skipping Unreleased while it is empty and omitting pull request lists.
newest_entries() {
    awk -v empty="$EMPTY" '
        function flush(    i, last, fence, line, pullrequests) {
            if (n == 0) return
            last = n
            while (last > 1 && buf[last] ~ /^[[:space:]]*$/) last--
            if (!(unreleased && !content) && taken < 2) {
                if (taken++) print ""
                fence = 0; pullrequests = 0
                for (i = 1; i <= last; i++) {
                    line = buf[i]
                    if (!fence && line ~ /^### /) {
                        pullrequests = (line == "### Pull requests")
                    }
                    if (pullrequests) continue
                    if (line ~ /^```/) fence = !fence
                    else if (!fence && line ~ /^#+ /) line = "#" line
                    print line
                }
            }
            n = 0
        }
        /^## / {
            flush()
            unreleased = ($0 == "## Unreleased"); content = 0
        }
        n || /^## / {
            buf[++n] = $0
            if (n > 1 && $0 !~ /^[[:space:]]*$/ && $0 != empty) content = 1
        }
        END {
            flush()
            if (!taken) print empty
        }
    ' CHANGELOG.md
}

replace_readme_block() {
    local block="$1"
    awk -v start="$START" -v end="$END" -v blockfile="$block" '
        $0 == start {
            print; print ""
            while ((getline line < blockfile) > 0) print line
            print ""; skip = 1; next
        }
        $0 == end { skip = 0 }
        !skip { print }
    ' README.md
}

readme() {
    if ! grep -qxF "$START" README.md || ! grep -qxF "$END" README.md; then
        fail "README.md needs the $START and $END markers."
    fi
    local block
    block="$(mktemp)"
    newest_entries > "$block"
    rewrite README.md replace_readme_block "$block"
    rm -f "$block"
}

case "${1:-}" in
    release)
        [ $# -eq 4 ] || usage
        rewrite CHANGELOG.md new_release_entry "$2" "$3" "$4" ||
            fail "CHANGELOG.md must start its entries with '## Unreleased'."
        readme
        ;;
    readme)
        [ $# -eq 1 ] || usage
        readme
        ;;
    *)
        usage
        ;;
esac
