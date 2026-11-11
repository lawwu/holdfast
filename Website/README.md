# Holdfast documentation site

Published at **https://lawwu.github.io/holdfast-docs/** using Astro and Starlight.
Documentation sources and workflows live in this Holdfast repository. Published
releases, including prereleases, deploy their tagged documentation to GitHub Pages.
Pull requests and pushes to `main` build and check the site without publishing.

## Edit the documentation

Edit the existing repository guides and package READMEs. `scripts/content.mjs`
explicitly lists the documents included in the public site. The getting-started,
architecture, and home pages live in `content/`. Versioned release notes under
`docs/releases/vX.Y.Z.md` are included automatically.

`npm run prepare-docs` creates `src/content/docs/` from these sources. Do not edit
that generated directory. Relative links to included documentation become site
links; other repository links still require access to the private source repo.
The interactive architecture guide is copied from `docs/local-mlx-architecture.html`.

From this directory, using Node 24.22.2 or a compatible newer version:

```sh
npm ci --ignore-scripts
npm run dev -- --host 127.0.0.1
```

For the same checks used in CI:

```sh
npm run build
npm test
npx playwright install chromium
npm run test:browser
```

The static check verifies links, fragments, assets, the Pages URL prefix, and the
search index. Browser checks cover desktop and mobile navigation, search, theme
selection, and horizontal overflow. No models or macOS build are needed.

## Publishing

`.github/workflows/pages.yml` publishes only `Website/dist/`. GitHub Pages isn't
available for the private app repository on its current plan, so the compiled
site lives in the separate public `lawwu/holdfast-docs` repository. Pages serves
that repository's `main` branch from `/`, with `.nojekyll`. The app's source code,
private commit history, model data, and evaluation results are not copied there.

The app repository's `DOCS_DEPLOY_KEY` Actions secret is a dedicated SSH private
key. Its public key is a write-enabled deploy key on `holdfast-docs` only. To rotate
it, replace both the repository secret and the matching public deploy key. No
personal access token is needed. Pull-request builds have no deployment step.

The deploy job uses the exact site artifact that passed checks, built from the
published release's commit. Public commits use a generic message rather than
exposing private commit messages. The Pages repository is generated output;
make edits in Holdfast.

The macOS release workflow calls the reusable docs workflow after successfully
publishing the installer. This explicit call is needed because releases created
with `GITHUB_TOKEN` do not trigger another workflow through the `release` event.
A `release: published` trigger also handles releases published outside Actions.
Drafts and unpublished tags cannot deploy, and a failed build leaves the live
site unchanged. [GitHub documents this token behavior](https://docs.github.com/en/actions/concepts/security/github_token).

To retry documentation only, run **Actions → Documentation → Run workflow** on
`main` and enter the published tag as `release_tag`. Leave it empty to check the
selected branch without deploying. The original `v0.0.1` predates the site and
cannot build documentation; automatic release deployment starts with a future
release containing `Website/`. No new app release is created by a docs deployment.

`site.mjs` defines the public origin and path prefix. Keep it in sync with the
deployment destination if the site moves. Public documentation does not make
the app's GitHub Releases publicly downloadable; those still require repository access.
