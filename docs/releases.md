# macOS releases

`VERSION` defines the app, preview extension, installer, and GitHub tag version.
The first release is `v0.0.1`, an Apple Silicon / macOS 15+ preview. Swift and npm
package versions remain independent of the app's release number.
The bundle build number defaults to the commit count on the release branch; use
`HOLDFAST_BUILD_NUMBER` to provide a different monotonically increasing build number.

The installer places `Holdfast.app` in `/Applications`. It has no installer scripts,
background services, bundled model weights, or user-vault payload. Upgrades replace
the app bundle as a unit; the installer does not relocate itself to a development copy.

## Automated unsigned prereleases

[macOS build and release](../.github/workflows/release.yml) builds on an Apple Silicon
macOS 15 runner with Xcode 26.3. Pull requests and pushes to `main` run the package,
Pi, release-guard, and installer checks and save the resulting installer as an Actions
artifact. They do not publish a GitHub release.

To publish a new version:

1. Update `VERSION` and add `docs/releases/vX.Y.Z.md`. Commit and push those changes
   to `main`, and wait for the build checks to pass.
2. Tag that commit and push the tag, for example:

   ```sh
   git tag -a v0.0.2 -m "Holdfast v0.0.2"
   git push origin v0.0.2
   ```

3. The workflow builds and tests the tagged source, uploads the exact tested `.pkg`,
   `SHA256SUMS`, `release-manifest.json`, and `verification.json` to a draft, then publishes
   it as an **unsigned prerelease**, never as the latest stable release.

The tag must match `VERSION`, belong to `main`, and contain its release notes. The workflow
never creates or moves tags, pushes commits, or replaces a published release. Use a new
version for changes to published assets. The existing `v0.0.1` remains the original release.

For a failed release, rerun the workflow or select **Actions → macOS build and release →
Run workflow** and enter its existing tag. Leave the tag empty to build and check the
selected branch without publishing. Choose a tag containing this workflow; older releases
are not repackaged with newer scripts. Concurrent runs for the same tag are serialized.

The build job has read-only repository access. Only the publication job receives
`contents: write`, using GitHub's built-in token. No Apple credentials or personal access
token are required. Actions are pinned to commits; Node follows `packaging/node-runtime.json`.
Swift build caches and npm download caches reduce repeated build work.

Cloud tests use scripted model responses to exercise the real Pi bridge and Holdfast's
Inbox approval, exact Undo, and stale-edit refusal. They **do not download models or run
MLX inference**. `verification.json` and the generated release notes state that explicitly.
Tests do not install the app into the runner's Applications folder.

## Local hardware testing

Build and test a local unsigned installer with an already downloaded model:

```sh
python3 scripts/build_release.py --unsigned-preview
python3 Tests/installer_integration.py "build/releases/$(cat VERSION)" \
  --live-mlx /path/to/an/installed/MLX/model --model-id mlx-community/Qwen3.5-2B-4bit
```

To test the exact CI-built installer instead, download its Actions artifact, extract all
four files into `build/releases/<version>/`, and run the same test against that directory.
The test records the installer checksum and whether real MLX inference ran. This local
result is separate from the cloud verification uploaded with the prerelease.

## Future Developer ID builds

The local scripts support signing and notarization. The automated workflow currently
always selects `--unsigned-preview`; enabling signed releases later requires changing it.

Install **Developer ID Application** and **Developer ID Installer** certificates
with their private keys in the signing Mac's Keychain. Use an Apple Developer Program
account to configure a `notarytool` Keychain profile. Do not commit certificates,
passwords, private keys, or API keys to this repository.

```sh
# Run interactively; credentials are stored in Keychain, not in a shell script.
xcrun notarytool store-credentials "holdfast-notary"

export HOLDFAST_SIGNING_IDENTITY="Developer ID Application: YOUR ORGANIZATION (TEAMID)"
export HOLDFAST_INSTALLER_IDENTITY="Developer ID Installer: YOUR ORGANIZATION (TEAMID)"
export HOLDFAST_NOTARY_PROFILE="holdfast-notary"
python3 scripts/build_release.py
python3 Tests/installer_integration.py "build/releases/$(cat VERSION)"
# Optional: add --live-mlx /path/to/an/installed/MLX/model --model-id its/model-id
```

The build requires committed release inputs. It bundles a checksum-pinned official
Node release, copies upstream license notices, signs nested code explicitly, signs
the installer, submits it to Apple, staples the accepted notarization ticket, and
checks Gatekeeper. Build artifacts and logs are under `build/releases/<version>/`.
Keep notarization logs locally for diagnosis; review warnings before publication.

The workflow calls `scripts/publish_release.py --tag vX.Y.Z --publish --allow-unsigned-preview`
after downloading the verified build artifacts. The publisher requires the matching tag
to be checked out; it checks the source revision, checksums and test results before uploading.
Omitting `--publish` leaves a draft. GitHub source archives come from the version tag.

See [Apple's signing and notarization guidance](https://developer.apple.com/developer-id/),
[the command-line notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
and [GitHub release management](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

## Local unsigned preview

Without Apple certificates, the complete packaging flow can still be tested locally:

```sh
python3 scripts/build_release.py --unsigned-preview
python3 Tests/installer_integration.py "build/releases/$(cat VERSION)"
```

This produces `Holdfast-0.0.1-macos-arm64-unsigned.pkg`. Its app uses an ad-hoc signature;
the installer has no Developer ID signature or notarization. It does not pass Apple's
normal distribution checks. The manifest, installer welcome screen, and draft release
state that clearly. Publishing this preview requires the explicit
`--publish --allow-unsigned-preview` flags; it is never marked as a stable/latest release.

## Runtime and validation

- `packaging/node-runtime.json` pins the official Node archive and SHA-256 digest.
  Updating the pin requires testing the Pi bridge and native modules with that Node version.
- Distribution builds use bundled Node and the bundled Pi runtime. Development builds
  can still use the checkout and an externally installed Node. Explicit `HOLDFAST_NODE`
  and `HOLDFAST_PI_DIR` overrides remain available.
- The app binary accepts explicit CLI commands, including `--version`, while opening
  the app normally shows its window. No global command-line shim is installed.
- Tests expand the exact installer and run its payload in an isolated app identity and
  synthetic vault with no developer runtime overrides. They also verify architecture,
  version, signature integrity, package destination, and absence of installer scripts.
- Verify first install and upgrade on a separate clean Mac before treating a preview
  as a stable release. Signing cannot be fully verified until real certificates and
  notarization credentials are configured.
