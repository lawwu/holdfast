# Holdfast documentation site

Published at **https://lawwu.github.io/holdfast/** using Astro and Starlight.
Documentation sources and workflows live in this Holdfast repository. Published
releases, including prereleases, deploy their tagged documentation to GitHub Pages.
Pull requests and pushes to `main` build and check the site without publishing.

## Edit the documentation

Edit the existing repository guides and package READMEs. `scripts/content.mjs`
explicitly lists the documents included in the public site. The getting-started,
architecture, and home pages live in `content/`. Versioned release notes under
`docs/releases/vX.Y.Z.md` are included automatically.

The root `README.md` is a short project introduction. The detailed app and CLI
reference lives in `docs/guide.md`, published at `/holdfast/guide/`.

`npm run prepare-docs` creates `src/content/docs/` from these sources. Do not edit
that generated directory. Relative links to included documentation become site
links; other repository links point to the public source on GitHub.
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

`.github/workflows/pages.yml` publishes only `Website/dist/` directly through
Holdfast's GitHub Pages configuration. The app, documentation, and deployment
workflow all live in `lawwu/holdfast`. No second repository, deploy key, personal
access token, or publishing branch is needed.

The build job uploads the tested site with `actions/upload-pages-artifact`.
The deploy job uses `actions/deploy-pages` with GitHub's built-in token and
`pages: write` / `id-token: write` permissions, scoped to that job. The release
workflow grants these permissions to its reusable documentation job as well.
Pull requests and ordinary main-branch pushes never run the deployment job.

The repository is public. **Settings → Pages → Build and deployment → Source**
is set to **GitHub Actions**. The `github-pages` environment allows `main` and
`v*` tags so both release events and manual retries can deploy.
[GitHub Pages configuration](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

The macOS release workflow calls the reusable docs workflow after successfully
publishing the installer. This explicit call is needed because releases created
with `GITHUB_TOKEN` do not trigger another workflow through the `release` event.
A `release: published` trigger also handles releases published outside Actions.
Drafts and unpublished tags cannot deploy, and a failed build leaves the live
site unchanged. [GitHub documents this token behavior](https://docs.github.com/en/actions/concepts/security/github_token).

To retry documentation only, run **Actions → Documentation → Run workflow** on
`main` and enter the published tag as `release_tag`. Leave it empty to check the
selected branch without deploying. The original `v0.0.1` predates the site and
cannot build documentation; automatic release deployment starts with
`v0.0.2`, which contains `Website/`. The initial site migration was published from
`main`; subsequent updates follow releases. No new app release is created by
a docs deployment.

`site.mjs` defines the public origin and path prefix. Keep it in sync with the
deployment destination if the site moves. Source code and installer releases
are publicly accessible from the Holdfast repository.

## Screenshots and the guided tour

The authored tour is `content/tour.mdx`; `src/components/TourPlayer.astro` provides
native video controls, English captions, and chapter buttons. All media is served
from this same Pages site, without an embedded third-party player. Playback never
autostarts.

`public/screenshots/` contains optimized captures of real app views using fictional
notes. `public/demo/` contains the reviewed video, captions, poster, and sample vault.
See `../Demo/README.md` for capture and narration instructions. The release publisher
uploads the same three downloadable demo files after verifying their hashes.
Rendering and paid narration stay local; Pages builds do not need an API key.
