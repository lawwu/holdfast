# macOS releases

`VERSION` defines the app, preview extension, installer, and GitHub tag version.
The first release is `v0.0.1`, an Apple Silicon / macOS 15+ preview. Swift and npm
package versions remain independent of the app's release number.
The bundle build number defaults to the commit count on the release branch; use
`HOLDFAST_BUILD_NUMBER` to provide a different monotonically increasing build number.

The installer places `Holdfast.app` in `/Applications`. It has no installer scripts,
background services, bundled model weights, or user-vault payload. Upgrades replace
the app bundle as a unit; the installer does not relocate itself to a development copy.

## Build a trusted release

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
python3 Tests/installer_integration.py build/releases/0.0.1
# Optional: add --live-mlx /path/to/an/installed/MLX/model --model-id its/model-id
python3 scripts/publish_release.py
```

The build requires committed release inputs. It bundles a checksum-pinned official
Node release, copies upstream license notices, signs nested code explicitly, signs
the installer, submits it to Apple, staples the accepted notarization ticket, and
checks Gatekeeper. Build artifacts and logs are under `build/releases/<version>/`.
Keep notarization logs locally for diagnosis; review warnings before publication.

The publish command creates or updates a **draft** GitHub prerelease with the installer,
checksums, and manifest. Inspect it, then run `python3 scripts/publish_release.py --publish`.
Published assets and existing tags are never silently replaced. An asset correction
after publication gets a new version. GitHub source archives come from the version tag.

See [Apple's signing and notarization guidance](https://developer.apple.com/developer-id/),
[the command-line notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
and [GitHub release management](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

## Local unsigned preview

Without Apple certificates, the complete packaging flow can still be tested locally:

```sh
python3 scripts/build_release.py --unsigned-preview
python3 Tests/installer_integration.py build/releases/0.0.1
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
