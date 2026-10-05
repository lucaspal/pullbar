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
- Release builds are signed with a Developer ID and notarized when the
  repository's `release` environment has the signing secrets, and ad-hoc
  signed otherwise.
- Each release is created as a draft and published only after a verify job
  has checked the downloaded app's signature (and notarization, when
  configured).
- `CHANGELOG.md`, with the two newest entries repeated at the end of the
  README.
- MIT license ([#3](https://github.com/lucaspal/Pullbar/pull/3)).

### Changed

- Renamed the project from "PR Inbox" to "pullbar": package, bundle
  identifier, sources, Keychain item, and docs
  ([#1](https://github.com/lucaspal/Pullbar/pull/1),
  [#2](https://github.com/lucaspal/Pullbar/pull/2)).
