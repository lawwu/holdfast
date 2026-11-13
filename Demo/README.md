# Holdfast walkthrough

A narrated walkthrough of real Holdfast views, using only the fictional notes in
`sample-vault/`. The video is edited for clarity: model waiting time is removed.
It is not a performance benchmark. Narration uses ElevenLabs' premade River voice.

Published files live in `Website/public/demo/`; screenshots live in
`Website/public/screenshots/`. `release-assets.json` records the three downloadable
assets' SHA-256 hashes. The website build verifies these before deployment.
The tour files are served on the website rather than attached to each app release.

## Capture real app views locally

Build the app with `-D HOLDFAST_DEMO_CAPTURE` into separate derived data, then package
it using a separate app path and bundle identifier (`app.holdfast.demo`). Normal
builds and distribution builds do **not** define this flag, so the capture driver
is absent from shipped apps.

Copy `sample-vault/` into ignored `build/demo/Sample Notes/`. Set the demo bundle's
`vault` preference to that copy and `migratedAppIdentityV2=true` to prevent importing
existing preferences. Use `general` for the sample vault's profile. Never use a
personal vault for these captures. The driver refuses vaults without the explicit
`.holdfast-demo` marker.

Launch the separate app through macOS `open --env`, setting `HOLDFAST_VAULT`,
`HOLDFAST_DEMO_CONTROL` to `build/demo/control`, and the desired local model.
The control folder must already exist. Index the sample notes first with the
app binary's `index --no-embed` command. Then use:

```sh
python3 Demo/capture.py pane Library
python3 Demo/capture.py open 'Kitchen repair plan' --shot library.png
python3 Demo/capture.py ask 'What did I decide about the kitchen repair?'
python3 Demo/capture.py status
```

Wait until `asking` is false and check the answer and sources before capturing.
The driver calls the real Store actions; it does not inject answers or proposals.
Capture Library, Answer settings, Ask, the source reader, Inbox before approval,
the updated checklist, and Recently filed with Undo. Confirm the proposed edit
leaves the file unchanged, Apply updates just the requested checkbox, and Undo
restores the original bytes. Screen recording permission is needed for macOS's
`screencapture`; Accessibility permission is not needed.

Keep raw PNGs in ignored `Demo/public/` for rendering, and export optimized WebP
copies for the site. Inspect every screenshot for legibility and private material.

## Narration and rendering

Review `scenes.json` against the captures before spending API credits. Use a key
in the environment; the generator never writes it into assets or logs. The optional
`--from-zshrc` reads a literal assignment without executing shell configuration.

```sh
python3 Demo/generate_voice.py
cd Demo
npm ci --ignore-scripts
npm run still
npm run render
```

The generator caches audio by narration/settings hash and uses actual ElevenLabs
character timestamps for caption timing. Re-running unchanged narration does not
make another paid request. Remotion uses those durations for each scene.

Check rendered frames, audio levels, duration, and caption alignment before copying
`out/holdfast-tour.mp4` and `public/holdfast-tour.vtt` into the website. Update the
release-asset hashes whenever any downloadable changes. No API key or narration
request runs in GitHub Actions; releases use reviewed, committed media.
