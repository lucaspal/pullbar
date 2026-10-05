#!/usr/bin/env bash
# Check that the unit tests catch real bugs.
#
# Usage: scripts/mutation-test.sh
#
# Each mutation below is one small, deliberate bug in the app's code: a
# flipped condition, a wrong label, a dropped filter. For each, the script
# applies it, runs `swift test`, and restores the file. A mutation the tests
# do not notice ("survived") means a missing or weak test. The script exits
# non-zero if any mutation survives, or if one no longer applies because the
# code changed (then update its pattern here).
#
# Run it on a clean working tree; it refuses otherwise, since it restores
# files with `git checkout`.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ -n "$(git status --porcelain -- Sources)" ]; then
    echo "error: Sources/ has uncommitted changes; commit or stash them first." >&2
    exit 1
fi

# file @@ perl substitution (applied once) @@ what the bug is
MUTATIONS=(
    "Sources/pullbar/Models.swift@@s/state == \.failure \|\| state == \.error/state == .failure/@@an ERROR check no longer counts as failing"
    "Sources/pullbar/Models.swift@@s/state == \.pending \|\| state == \.expected/state == .pending/@@an EXPECTED check no longer counts as pending"
    "Sources/pullbar/Models.swift@@s/ \|\| mergeable == \.conflicting\n/\n/@@a merge conflict no longer needs action"
    "Sources/pullbar/Models.swift@@s/ \|\| reviewDecision == nil//@@no review required no longer counts as ready"
    "Sources/pullbar/Models.swift@@s/checks == nil \|\| //@@no checks no longer counts as ready"
    "Sources/pullbar/Models.swift@@s/if isDraft \{ return \"Not ready\" \}//@@drafts show their review state"
    "Sources/pullbar/Models.swift@@s/case \.reviewRequired: return \"Awaiting approval\"/case .reviewRequired: return \"Approved\"/@@wrong review label"
    "Sources/pullbar/Models.swift@@s/filter \{ !direct\.contains/filter { direct.contains/@@team requests become direct requests"
    "Sources/pullbar/Models.swift@@s/\\\$0\.updatedAt > \\\$1\.updatedAt/\\\$0.updatedAt < \\\$1.updatedAt/@@sections sorted oldest first"
    "Sources/pullbar/Models.swift@@s/if pr\.isDraft \{/if false {/@@drafts are not recognised"
    "Sources/pullbar/Models.swift@@s/case \.waitingForReviewOrChecks: return \"All caught up\"/case .waitingForReviewOrChecks: return \"\"/@@empty section text lost"
    "Sources/pullbar/Settings.swift@@s/case \.week: return 7/case .week: return 8/@@wrong window length"
    "Sources/pullbar/Settings.swift@@s/value: -days/value: days/@@updated filter looks into the future"
    "Sources/pullbar/Settings.swift@@s/return v > 0 \? v : 120/return v > 0 ? v : 60/@@wrong default refresh interval"
    "Sources/pullbar/Settings.swift@@s/\?\? \.month/?? .week/@@wrong default updated window"
    "Sources/pullbar/GitHubClient.swift@@s/\[\"SUCCESS\", \"NEUTRAL\", \"SKIPPED\"\]/[\"SUCCESS\", \"NEUTRAL\"]/@@skipped checks no longer pass"
    "Sources/pullbar/GitHubClient.swift@@s/case \"StatusContext\":\n\s+return state == \"SUCCESS\"/case \"StatusContext\":\n                        return state != \"FAILURE\"/@@pending statuses count as passed"
    "Sources/pullbar/GitHubClient.swift@@s/statusCode == 401/statusCode == 403/@@401 not reported as a bad token"
    "Sources/pullbar/GitHubClient.swift@@s/!errors\.isEmpty, envelope\.data == nil/!errors.isEmpty/@@partial data thrown away"
    "Sources/pullbar/GitHubClient.swift@@s/\?\? \"ghost\"/?? \"\"/@@missing author not shown as ghost"
    "Sources/pullbar/GitHubClient.swift@@s/\"is:pr \\\\\(query\)\"/\"\\\\(query)\"/@@searches include issues"
    "Sources/pullbar/GitHubClient.swift@@s/\"Bearer \\\\\(token\)\"/\"token \\\\(token)\"/@@wrong authorization header"
    "Sources/pullbar/GitHubClient.swift@@s/user-review-requested:\@me/review-requested:\@me/@@direct review requests not searched"
    "Sources/pullbar/InboxService.swift@@s/\"archived:false\", //@@archived repositories included"
    "Sources/pullbar/Keychain.swift@@s/return token\.isEmpty \? nil : token/return token/@@empty token treated as a token"
    "Sources/pullbar/Keychain.swift@@s/deleteToken\(service: service\)\n        var attrs/var attrs/@@writing over an existing token fails"
    "Sources/pullbar/TokenProvider.swift@@s/== \.command \&\&/!= [] \&\&/@@any modifier pastes"
    "Sources/pullbar/TokenProvider.swift@@s/intersection\(\[\.command, \.shift, \.option, \.control\]\)/intersection(.deviceIndependentFlagsMask)/@@Caps Lock stops Cmd-V from pasting"
    "Sources/pullbar/TokenProvider.swift@@s/guard process\.terminationStatus == 0 else \{ return nil \}//@@a failing gh command still gives a token"
    "Sources/pullbar/AppDelegate.swift@@s/title \+= \"\+\\\\\(teams\)\"/title += \"-\\\\(teams)\"/@@team count shown wrongly"
    "Sources/pullbar/AppDelegate.swift@@s/if error != nil \{\n\s+title = /if false {\n                title = /@@failed refresh not flagged"
    "Sources/pullbar/AppDelegate.swift@@s/String\(s\.prefix\(max - 1\)\)/String(s.prefix(max))/@@truncated titles too long"
    "Sources/pullbar/AppDelegate.swift@@s/seconds < 120 \?/seconds <= 120 ?/@@wrong interval label"
    "Sources/pullbar/AppDelegate.swift@@s/inbox == nil \? \"Loading…\" : section\.emptyText/section.emptyText/@@no loading state"
    "Sources/pullbar/AppDelegate.swift@@s/item\.representedObject = pr\.url/item.representedObject = nil/@@clicking a pull request opens nothing"
)

# More mutations, one file per feature: one entry per line in the same
# format, written as-is (no shell quoting). A pull request that adds a
# feature adds its own file, so pull requests don't all edit the list above.
for list in scripts/mutations/*.txt; do
    [ -e "$list" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        MUTATIONS+=("$line")
    done < "$list"
done

echo "Baseline: the tests must pass before mutating."
if ! swift test >/tmp/mutation-baseline.log 2>&1; then
    echo "error: tests fail without any mutation; see /tmp/mutation-baseline.log" >&2
    exit 1
fi

killed=0
survived=()
stale=()
for entry in "${MUTATIONS[@]}"; do
    file="${entry%%@@*}"
    rest="${entry#*@@}"
    expr="${rest%@@*}"
    label="${rest##*@@}"
    before="$(shasum "$file")"
    perl -0pi -e "$expr" "$file"
    if [ "$(shasum "$file")" = "$before" ]; then
        stale+=("$label ($file)")
        echo "STALE    $label"
        continue
    fi
    if swift test >/dev/null 2>&1; then
        survived+=("$label ($file)")
        echo "SURVIVED $label"
    else
        killed=$((killed + 1))
        echo "killed   $label"
    fi
    git checkout -- "$file"
done

total=${#MUTATIONS[@]}
echo
echo "$killed of $total mutations caught by the tests."
for m in ${survived[@]+"${survived[@]}"}; do echo "  survived: $m"; done
for m in ${stale[@]+"${stale[@]}"}; do echo "  no longer applies: $m"; done
[ ${#survived[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ]
