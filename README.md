# pullbar

<!-- Relative links, so each fork's README shows that fork's own build and releases. -->
[![Build](../../actions/workflows/build.yml/badge.svg?branch=main)](../../actions/workflows/build.yml)
[![Releases](https://img.shields.io/badge/download-releases-blue)](../../releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)

pullbar is a native macOS menu bar app for checking your open GitHub pull
requests without opening a browser. It reads GitHub's GraphQL API and presents
six inbox-style sections in a menu-bar popover. It has no Dock icon or main
window.

![pullbar menu example](pullbar-screenshot.png)

## What it shows

The app runs three GitHub searches for the signed-in user: pull requests
requested from you, requested directly from you, and authored by you. It then
sorts the resulting pull requests by update time into these sections:

- **Needs your review** — returned by `user-review-requested:@me`.
- **Needs your teams' review** — returned by `review-requested:@me`, excluding
  pull requests already in **Needs your review**.
- **Your drafts** — your open draft pull requests.
- **Waiting for review or checks** — your non-draft pull requests that neither
  need action nor meet this app's ready-to-merge conditions.
- **Needs action** — your pull requests with changes requested, a failing check
  rollup, or a merge conflict.
- **Ready to merge** — your non-draft, non-conflicting pull requests whose
  review decision is approved or not required and whose check rollup is
  successful (or absent).

For each pull request, the menu displays its repository and number, author,
last-updated time, review state, check summary, merge-conflict indicator, and
comment count. Selecting a row opens that pull request in the default browser.

The menu-bar title shows the count needing your review. If there are team
requests, it appends their count (for example, `5+1`); if one of your pull
requests needs action, it appends `⚠︎` and that count. Hover over the title to
see the counts for all six sections.

## Requirements

- A Mac with Apple Silicon (M1 or later). Intel Macs are not supported: the
  release app is built for `arm64` only.
- macOS 13 Ventura or later
- Xcode Command Line Tools, which provide `swift`
- A GitHub personal access token, or an authenticated GitHub CLI (`gh`) session

The project uses only Apple frameworks: AppKit, Foundation, Security, and
ServiceManagement.

## Build and run

Run these commands from the repository root:

```sh
make install
```

`make install` builds a release app bundle, installs it as
`~/Applications/pullbar.app`, and opens it. The bundle is ad-hoc signed, so
macOS may ask you to confirm its first launch.

| Command | Result |
|---|---|
| `make build` | Builds the release executable in `.build/release/`. |
| `make run` | Builds and runs the release executable directly, without an app bundle. |
| `make test` | Runs the unit tests. |
| `make mutation-test` | Checks that the tests catch deliberate bugs. |
| `make app` | Creates the ad-hoc-signed `build/pullbar.app` bundle. |
| `make app VERSION=1.2.3` | Same, with `1.2.3` as the app version (used by the release workflow). |
| `make install` | Creates the bundle, copies it to `~/Applications`, and opens it. |
| `make clean` | Removes `.build` and `build`. |

**Launch at login** is available only when the app runs from a packaged `.app`
bundle, including the one installed by `make install`.

### Fake data (fixtures)

To see how the menu renders without a GitHub account, or to take a
screenshot without showing real pull requests, start the app with a fixture:

```sh
make app
open build/pullbar.app --args --fixture "$PWD/Fixtures/showcase.json"
```

The app then shows the made-up inbox from that JSON file instead of asking
GitHub, and does not read or ask for a token. It reads the file again every
time the menu opens, so edits show up on the next open.

| Fixture | Shows |
|---|---|
| `Fixtures/showcase.json` | Every section and state: drafts, pending, failing and passing checks, changes requested, a conflict, team requests, and large comment counts. |
| `Fixtures/empty.json` | An inbox with nothing in it. |
| `Fixtures/error.json` | A failed refresh: the error banner above a partial inbox. |

In a fixture, `direct` and `teams` are review requests and `authored` are
your own pull requests, which the app sorts into sections by the same rules
as real data. `updated` is relative (`45m`, `3h`, `2d`, `5w`), so a fixture
looks the same whenever it is shown. See `Sources/pullbar/Fixture.swift` for
every field.

## Authentication and stored data

At launch, the app obtains a token in this order:

1. A token stored in the login Keychain under the pullbar GitHub-token item.
2. The output of `gh auth token`, if the GitHub CLI is installed and logged in.
3. A secure token prompt.

A token entered in the prompt is used immediately and the app attempts to save
it in the login Keychain. Use **Set GitHub token…** in the menu to replace the
saved token. The prompt supports standard **⌘V** paste.

Use a personal access token that GitHub permits to query the pull requests you
want to see. The required scopes or fine-grained permissions depend on the
private repositories and organisations involved; GitHub reports insufficient
permission as an error in the menu.

pullbar stores the saved token in Keychain. Its update-window and refresh
interval preferences are stored in the app's `UserDefaults`; it does not store
pull-request results on disk.

## Menu controls

- **Open inbox on GitHub** opens `https://github.com/pulls/inbox` (**⌘O**).
- **Refresh now** starts a new fetch (**⌘R**). Opening the menu also starts a
  refresh when the last successful result is at least 30 seconds old. Failed
  refreshes are retried when the menu opens; an in-progress fetch is not
  duplicated.
- **Updated** filters searches to **Last week**, **Last month** (the default),
  **Last 3 months**, or **Any time**. Changing it refreshes the inbox.
- **Refresh every** schedules automatic refreshes every 1, 2 (the default), 5,
  or 15 minutes.
- **Launch at login** enables or disables the packaged app's macOS login item.
- **Quit pullbar** quits the app (**⌘Q**).

When a fetch fails, the menu shows the error and provides **Set GitHub token…**
to update credentials.

## Data-fetching limits and details

Each refresh sends the three inbox searches as GraphQL aliases in one request
per page. Each search requests 100 items per page, the most GitHub allows and
no more expensive than 50, and reads at most four pages, so a search is limited
to 400 pull requests per refresh. Searches that have finished paging are
omitted from later requests. Below 10% API budget remaining, automatic refresh
waits up to 15 minutes or until the budget resets, if sooner. A rate-limit
response pauses refreshes until GitHub's reset time, using `Retry-After` when
provided.

Search queries include `is:pr`, `is:open`, `archived:false`,
`sort:updated-desc`, and the selected updated-time filter.

For each returned pull request, the app reads the latest commit's
`statusCheckRollup` with GitHub's per-state counts of check runs and status
contexts, so the displayed check total and passed count include every check,
however many there are, without paging through them.

## Testing

```sh
make test            # or: swift test
make mutation-test   # or: scripts/mutation-test.sh
```

The unit tests in `Tests/pullbarTests/` cover the inbox rules (which section a
pull request lands in, sorting, the review and check labels), the settings,
reading GitHub's GraphQL responses and errors through a stubbed network, the
three inbox searches, the Keychain (using a throwaway item, never your
token), the `gh` token lookup, the menu bar title, and the menu's contents.
The parts that need a real screen or the system are not unit tested: the
token prompt, the status bar item itself, opening URLs, and login items.

`make mutation-test` checks that the tests catch real bugs. It applies a list
of small, deliberate bugs to the code one at a time, such as a flipped
condition, a wrong label, or a dropped search filter, and runs the tests
after each. Every one must make a test fail; a bug that goes unnoticed means
a missing test. When you change logic, add a test for it, and add a mutation
for any rule the existing ones do not cover: to `scripts/mutation-test.sh`,
or, for a new feature, to its own file in `scripts/mutations/` (one entry per
line, same format), so feature pull requests don't all edit the same list.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/pullbar/PullbarApp.swift` | Application entry point and menu-bar-only activation policy. |
| `Sources/pullbar/AppDelegate.swift` | Menu, status title, refresh scheduling, and menu actions. |
| `Sources/pullbar/GitHubClient.swift` | GitHub GraphQL client and pagination. |
| `Sources/pullbar/InboxService.swift` | The three aliased inbox searches. |
| `Sources/pullbar/Models.swift` | Pull-request models and section classification. |
| `Sources/pullbar/TokenProvider.swift` | Keychain, GitHub CLI, and token-prompt lookup. |
| `Sources/pullbar/Keychain.swift` | Login-Keychain storage. |
| `Sources/pullbar/Settings.swift` | `UserDefaults` settings. |
| `Sources/pullbar/Fixture.swift` | Loads a made-up inbox from JSON (`--fixture`). |
| `Fixtures/` | Example fixture files. |
| `Packaging/` | App metadata and icon-build script. |
| `Tests/pullbarTests/` | Unit tests. |
| `scripts/mutation-test.sh` | Mutation test: deliberate bugs the tests must catch. |
| `Makefile` | Build, bundle, install, and clean targets. |
| `scripts/create-release.sh` | Prepares a release branch: changelog entry and README section. |
| `scripts/release-notes.sh` | Lists the pull requests merged since the previous tag, for release notes and the changelog. |
| `scripts/changelog.sh` | Edits `CHANGELOG.md` and the README changelog section. |
| `scripts/check-release-tag.sh` | Release workflow check: the tag is on the release commit for its version. |
| `scripts/protect-release-tags.sh` | One-time setup: only admins may push `v*` tags. |
| `.github/workflows/build.yml` | CI build and tag-triggered GitHub release. |
| `CHANGELOG.md` | Summary of changes per release. |
| `LICENSE` | MIT license terms. |

## License

pullbar is available under the [MIT License](LICENSE).

## Changelog

The two most recent entries from [CHANGELOG.md](CHANGELOG.md). See that file
for older versions, and the
[GitHub releases](../../releases) page for the
full notes (one entry per merged pull request) and a downloadable
`pullbar.app` zip.

Releases are built only from `main`. `scripts/create-release.sh v1.2.0`
prepares the changelog and this section on a release branch; after that
branch is merged, pushing the `v1.2.0` tag on the merge commit makes the
**Build** workflow build, sign, and publish the release. See `AGENTS.md` for
the steps.

Two safeguards keep releases to that process:

- The workflow builds a release only when the tag points at the commit that
  added the version's `CHANGELOG.md` entry, that is, the merged release pull
  request (`scripts/check-release-tag.sh`). Tagging any other commit fails.
- Tag rules are separate from the rules protecting `main`. Run
  `scripts/protect-release-tags.sh` once (it needs admin rights) so only
  repository admins can create, move, or delete `v*` tags.

<!-- changelog:start -->

### Unreleased

#### Added

- GitHub Actions workflow that builds and signature-checks the app on every
  push to `main` and every pull request, and publishes a GitHub release with
  the app zip when a `vX.Y.Z` tag is pushed on the merged release pull
  request. `scripts/protect-release-tags.sh` limits `v*` tags to admins.
- `scripts/create-release.sh vX.Y.Z` prepares a release branch with the
  `CHANGELOG.md` entry, a list of the pull requests merged since the previous
  tag, and the README changelog section. No dependencies beyond git, `gh`,
  bash, and awk.
- `make app VERSION=X.Y.Z` stamps the version into the app bundle.
- `CHANGELOG.md`, with the two newest entries repeated at the end of the
  README.
- MIT license ([#3](https://github.com/lucaspal/Pullbar/pull/3)).

#### Changed

- Renamed the project from "PR Inbox" to "pullbar": package, bundle
  identifier, sources, Keychain item, and docs
  ([#1](https://github.com/lucaspal/Pullbar/pull/1),
  [#2](https://github.com/lucaspal/Pullbar/pull/2)).

<!-- changelog:end -->
