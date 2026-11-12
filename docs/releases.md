# macOS releases

`VERSION` defines the app, preview extension, installer, and GitHub tag version.
The first release is `v0.0.1`, an Apple Silicon / macOS 15+ preview. Swift and npm
package versions remain independent of the app's release number.
The bundle build number defaults to the commit count on the release branch; use
`HOLDFAST_BUILD_NUMBER` to provide a different monotonically increasing build number.

The installer places `Holdfast.app` in `/Applications`. It has no installer scripts,
background services, bundled model weights, or user-vault payload. Upgrades replace
the app bundle as a unit; the installer does not relocate itself to a development copy.

Each release also offers a read-only DMG containing the same app. Open the
disk image, then right-click **Holdfast.app → Install with Privilege Management**
when your organization's Finder integration permits it. The DMG does not change
Gatekeeper or management policy. BeyondTrust documents this flow for application
bundles in [mounted disk images](https://docs.beyondtrust.com/epm-wm/v25.6/docs/gpo-macos-policies).
The PKG remains available for standard or centrally managed installation.

`python3 scripts/package_release_dmg.py build/releases/<version>` extracts the
already tested installer, creates the DMG, mounts it read-only, and verifies every
app file, symlink, executable bit, signature, and bundled runtime version. Its
separate `.dmg.sha256` and `dmg-verification.json` identify both the DMG and its
source installer. It does not claim to test an organization's privilege policy.
For a signed release it also signs the disk image with Developer ID, notarizes and
staples it, and checks it and the mounted app with Gatekeeper; an unsigned preview
gets an unsigned `-unsigned.dmg`.

## Automated signed releases

[macOS build and release](../.github/workflows/release.yml) builds on an Apple Silicon
`xcode-27` runner with Xcode 27.2. The pinned MLX dependencies require Swift 6.3;
the installer still targets macOS 15 or later. Pull requests and pushes to `main` run the package,
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

3. The workflow builds and tests the tagged source, packages the same app in a DMG,
   uploads the verified `.pkg`, `.dmg`, DMG checksum and verification report,
   `SHA256SUMS`, `release-manifest.json`, and `verification.json` to a draft, then publishes
   it as the **latest release**. Before it starts, GitHub asks the owner to approve the
   `release` environment; only then does the build receive the signing secrets, sign
   with Developer ID, and notarize the installer and the DMG.
4. After publication, it builds and tests the documentation from the same tag and
   deploys it to GitHub Pages. A failed docs deployment leaves the existing site up;
   retry it through **Actions → Documentation** with that published `release_tag`.

Documentation sources live in this repository. Main-branch pushes and pull requests
check the site without deploying; releases published manually also trigger deployment.
See [site maintenance](../Website/README.md) for the hosting setup and local checks.

The tag must match `VERSION`, belong to `main`, and contain its release notes. The workflow
never creates or moves tags, pushes commits, or replaces a published release. Use a new
version for changes to published assets. The existing `v0.0.1` remains the original release.

For a failed release, rerun the workflow or select **Actions → macOS build and release →
Run workflow** and enter its existing tag. Leave the tag empty to build and check the
selected branch without publishing. Choose a tag containing this workflow; older releases
are not repackaged with newer scripts. Concurrent runs for the same tag are serialized.

The build job has read-only repository access. Only the publication job receives
`contents: write`, using GitHub's built-in token. Apple credentials live only in the
protected `release` environment (below); pull requests and `main` pushes never see them
and build the unsigned preview. Actions are pinned to commits; Node follows `packaging/node-runtime.json`.

### Signing secrets

The `release` environment (**Settings → Environments → release**) has the owner as a
required reviewer, deployment limited to `v*` tags, and five secrets:

| Secret | What it holds |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of a `.p12` exported from Keychain Access with both Developer ID Application and Developer ID Installer certificates and their private keys |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting it |
| `NOTARY_KEY_BASE64` | Base64 of an App Store Connect API key (`AuthKey_….p8`; Users and Access → Integrations → Team Keys, Developer access) |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the keys list |

The workflow loads them into a temporary keychain on the runner, adds Apple's pinned
Developer ID G2 intermediate, finds the two identities by name, and deletes the keychain
and key file when the build ends. A release tag with any secret missing fails before
building. Set them with the GitHub CLI so the values never appear in a terminal or file:

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env release
gh secret set DEVELOPER_ID_P12_PASSWORD --env release
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_BASE64 --env release
gh secret set NOTARY_KEY_ID --env release
gh secret set NOTARY_ISSUER_ID --env release
```
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
result is separate from the cloud verification uploaded with the release.

## Signed builds on a Mac

The same scripts sign and notarize locally. Install **Developer ID Application** and
**Developer ID Installer** certificates with their private keys in the Mac's Keychain,
plus Apple's Developer ID G2 intermediate, and store a `notarytool` Keychain profile
(or set `HOLDFAST_NOTARY_KEY`, `HOLDFAST_NOTARY_KEY_ID` and `HOLDFAST_NOTARY_ISSUER`
to use an API key, as CI does). Do not commit certificates, passwords, private keys,
or API keys to this repository.

```sh
# Run interactively; credentials are stored in Keychain, not in a shell script.
xcrun notarytool store-credentials "holdfast-notary"

export HOLDFAST_SIGNING_IDENTITY="Developer ID Application: YOUR ORGANIZATION (TEAMID)"
export HOLDFAST_INSTALLER_IDENTITY="Developer ID Installer: YOUR ORGANIZATION (TEAMID)"
export HOLDFAST_NOTARY_PROFILE="holdfast-notary"
python3 scripts/build_release.py
python3 Tests/installer_integration.py "build/releases/$(cat VERSION)"
# Optional: add --live-mlx /path/to/an/installed/MLX/model --model-id its/model-id
python3 scripts/package_release_dmg.py "build/releases/$(cat VERSION)"
```

The build requires committed release inputs. It bundles a checksum-pinned official
Node release, copies upstream license notices, signs nested code explicitly, signs
the installer, submits it to Apple, staples the accepted notarization ticket, and
checks Gatekeeper. Build artifacts and logs are under `build/releases/<version>/`.
Keep notarization logs locally for diagnosis; review warnings before publication.

The workflow calls `scripts/publish_release.py --tag vX.Y.Z --publish --include-dmg`
after downloading the verified build artifacts; without `--allow-unsigned-preview` it
refuses anything not signed and notarized. The publisher requires the matching tag
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
- Verify first install and upgrade on a separate clean Mac after a signing change:
  download the release in a browser (so it is quarantined) and confirm it opens
  without a Gatekeeper prompt.

### Walkthrough downloads

Releases from v0.0.2 include the reviewed walkthrough MP4, English WebVTT captions,
and a ZIP of fictional sample notes. `Demo/release-assets.json` pins their SHA-256
hashes. Publication verifies all three committed files and uploads them before
publishing the release; a missing or changed asset stops publication. The website
serves the same files. Narration and video rendering run locally, without API keys
in GitHub Actions. See [the demo workflow](../Demo/README.md).
