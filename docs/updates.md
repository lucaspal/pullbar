# Releases and automatic updates without an Apple membership

Sparkle 2.10.1 is MIT licensed. Its Ed25519 update signatures do not require an
Apple Developer account. GitHub hosts the release ZIPs and the appcast. Standard
GitHub-hosted Actions runners are free for public repositories; GitHub's normal
usage and storage limits still apply. No paid service is required for this design.

The app integration is implemented locally. The release-workflow extension is
pending approval. Apply and test that extension before publishing an app with
updates enabled; the existing workflow does not yet publish an appcast.

## Installing and updating

Download the release ZIP, extract `pullbar.app`, move it into Applications or
`~/Applications`, and open it. The app is ad-hoc signed, not Apple-notarized.
macOS may block its first launch; follow Apple's instructions to allow an app
from an unidentified developer in System Settings > Privacy & Security.

The menu includes **Check for updates…**. When configured, Sparkle checks the
stable appcast, verifies the update's signature before extraction, and offers
to download, install, and relaunch. Sparkle manages permission to check in the
background and automatic installation preferences. Pre-releases do not replace
the stable feed because it uses GitHub's `releases/latest` download URL.

An existing source installation needs one manual upgrade to a build containing
Sparkle and the maintainer's public signing key. A bare `make run` executable
cannot update itself. Translocated apps must be moved to Applications first.
Installs under Homebrew's Cellar/Caskroom use Homebrew instead of self-updating.
Builds without update configuration leave the menu item disabled with a reason.

Apple Developer ID signing and notarization are optional separate improvements
for a smoother initial installation. They are not prerequisites for Sparkle.
The complete install/relaunch flow still needs an end-to-end test using two
real signed releases on supported macOS before claiming release readiness.

## One-time maintainer setup

The maintainer runs these commands personally. Do not paste private keys into
chat or commit them. Agents must not create, read, or upload signing secrets.

1. Configure GitHub's `release` environment to accept **selected tags `v*` only**.
   Do this before storing a key. Protect release tags and the main branch as
   described in `AGENTS.md`; keep signing keys out of repository-level secrets.
2. Resolve the pinned tools and generate your key in the local login Keychain:

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account pullbar-release
   ```

3. Save the printed **public** key as the repository Actions variable
   `SPARKLE_PUBLIC_KEY`. It is embedded in every update-enabled app. For local
   builds, supply the same public key with `SPARKLE_PUBLIC_KEY='…' make install`.
4. Export the private key temporarily and store it as the **release environment**
   secret `SPARKLE_PRIVATE_KEY`, using standard input rather than a command-line
   argument:

   ```sh
   key_directory="$(mktemp -d)"
   key_file="$key_directory/sparkle-private-key"
   (umask 077; .build/artifacts/sparkle/Sparkle/bin/generate_keys --account pullbar-release -x "$key_file")
   gh secret set SPARKLE_PRIVATE_KEY --repo lucaspal/Pullbar --env release < "$key_file"
   rm "$key_file"
   rmdir "$key_directory"
   ```

   Keep a secure backup of the signing key. Without Developer ID signing,
   losing this key requires users to install a replacement build manually.

## Proposed pipeline behavior

The pending workflow extension adds a tag-only signing job after build and
tests. The normal build sees only the public key. The signing job alone accesses
`SPARKLE_PRIVATE_KEY` from the protected `release` environment.

That job downloads the exact built ZIP, verifies its app version, architecture,
feed URL, public key and nested code signatures, then runs Sparkle's pinned
`generate_appcast` and `sign_update` tools. The resulting archive and signed
appcast must both verify before the publishing job can run. Missing or
mismatched keys stop the release. Private key material is passed over stdin.

The release contains `pullbar-<version>-darwin-arm64.zip` and `appcast.xml`.
The app reads its own repository's feed at:

```text
https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml
```

`make app VERSION=X.Y.Z` stamps both the display version and the updater's
comparison version. Existing changelog, release PR, green main, and tag checks
continue to apply. A passing PR build does not prove the signing/publishing job:
verify a complete tag run before treating the release as tested.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[GitHub Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage),
[Apple membership](https://developer.apple.com/programs/).
