# Changelog

Notable changes to pullbar, newest first. Versions follow
[Semantic Versioning](https://semver.org/).

Each [GitHub release](../../releases) has the
full notes: the title, author, and description of every pull request merged
since the previous release. This file is the short summary.

Add notable changes under **Unreleased** as you go; this is optional, since
each release also lists its merged pull requests. `scripts/create-release.sh`
turns Unreleased into the release entry and adds that list; `AGENTS.md`
describes the release steps. Keep **Unreleased** as the first entry.

## Unreleased

_Nothing yet._

## [1.2.0](https://github.com/lucaspal/Pullbar/releases/tag/v1.2.0) - 2026-10-28

### Pull requests

- Keep release history in CHANGELOG.md instead of duplicating it in README ([#35](https://github.com/lucaspal/pullbar/pull/35)) by @lucaspal
- Add merge queue section and Sparkle app integration ([#36](https://github.com/lucaspal/pullbar/pull/36)) by @lucaspal

## [1.1.0](https://github.com/lucaspal/Pullbar/releases/tag/v1.1.0) - 2026-10-28

### Added

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

### Changed

- Renamed the project from "PR Inbox" to "pullbar": package, bundle
  identifier, sources, Keychain item, and docs
  ([#1](https://github.com/lucaspal/Pullbar/pull/1),
  [#2](https://github.com/lucaspal/Pullbar/pull/2)).

### Pull requests

- Rename/rebrand project from "PR Inbox" to "pullbar" ([#1](https://github.com/lucaspal/pullbar/pull/1)) by @lucaspal
- Rebrand PR Inbox to pullbar (package, bundle, sources, docs, license) ([#2](https://github.com/lucaspal/pullbar/pull/2)) by @lucaspal
- Add MIT license ([#3](https://github.com/lucaspal/pullbar/pull/3)) by @lucaspal
- Add agent guide for screenshots and releases ([#4](https://github.com/lucaspal/pullbar/pull/4)) by @christhomas
- Add CI build, tag-triggered releases, and changelog ([#5](https://github.com/lucaspal/pullbar/pull/5)) by @christhomas
- Line up the status columns in pull request rows ([#6](https://github.com/lucaspal/pullbar/pull/6)) by @christhomas
- Enable Dependabot for GitHub Actions ([#7](https://github.com/lucaspal/pullbar/pull/7)) by @christhomas
- Add fixture files for showing a made-up inbox ([#8](https://github.com/lucaspal/pullbar/pull/8)) by @christhomas
- Make Launch at login work for every way of installing pullbar ([#10](https://github.com/lucaspal/pullbar/pull/10)) by @christhomas
- Show the app version and where the build came from at the top of the menu ([#12](https://github.com/lucaspal/pullbar/pull/12)) by @christhomas
- Say in the README that pullbar needs an Apple Silicon Mac ([#13](https://github.com/lucaspal/pullbar/pull/13)) by @christhomas
- Keep the open menu in sync with background refreshes ([#14](https://github.com/lucaspal/pullbar/pull/14)) by @christhomas
- Add unit tests, a mutation test that proves they catch bugs, and exact check counts ([#15](https://github.com/lucaspal/pullbar/pull/15)) by @christhomas
- Let Cmd-V paste into the token prompt when Caps Lock is on ([#16](https://github.com/lucaspal/pullbar/pull/16)) by @christhomas
- Ask for 100 search results per page instead of 50 ([#22](https://github.com/lucaspal/pullbar/pull/22)) by @christhomas
- Group pull requests by owner, with the owner in bold ([#23](https://github.com/lucaspal/pullbar/pull/23)) by @christhomas
- Show how much of the GitHub API budget pullbar has used ([#24](https://github.com/lucaspal/pullbar/pull/24)) by @christhomas
- Keep the GitHub token when upgrading from PR Inbox ([#27](https://github.com/lucaspal/pullbar/pull/27)) by @christhomas
- [Draft] Reduce inbox API requests and respect rate limits ([#31](https://github.com/lucaspal/pullbar/pull/31)) by @lucaspal
- Bump the github-actions group with 2 updates ([#32](https://github.com/lucaspal/pullbar/pull/32)) by @app/dependabot
- docs: document release setup and publishing workflow ([#33](https://github.com/lucaspal/pullbar/pull/33)) by @lucaspal
