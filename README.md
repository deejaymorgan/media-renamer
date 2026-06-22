# Media Renamer

A native **macOS (SwiftUI)** app that restructures a folder of `.mkv` files (and
subtitle sidecars) into a Plex/Jellyfin-friendly tree:

- **TV:** `Show Name/Season N/Show Name S##E##.mkv`
- **Movie:** `Movie Name (Year)/Movie Name (Year).mkv`

Pick a folder → preview the plan → tweak titles, set acronym casing, choose which
junk to trash, resolve duplicate versions → **Apply**. Nothing on disk changes
until you press Apply, and it asks for confirmation first.

A ground-up Swift rebuild of an earlier (unpublished) Python CLI, which is kept
privately only as the behavioural spec and test oracle — no Python ships here.
See [`SPEC.md`](SPEC.md) for the full design and roadmap.

## Screenshots & quick start

A step-by-step walkthrough with screenshots is at the
**[Quick Start guide](https://deejaymorgan.github.io/media-renamer/)** (rendered
via GitHub Pages). It also ships in the repo as
[`docs/quickstart.html`](docs/quickstart.html), with a
[PDF version](docs/quickstart.pdf).

## ⚠️ Safety

This app **renames and moves your files** and sends unwanted "junk" to the macOS
**Trash**. The preview is read-only — only **Apply** touches disk, and it confirms
first. Renaming never overwrites, and trashed files can be restored with Finder's
**Put Back** — but treat Apply as a real, bulk filesystem operation and
**run it on a copy of your media first**, until you trust the results.

Full safety notes are in the
[Quick Start guide](https://deejaymorgan.github.io/media-renamer/).

## Requirements

- **macOS 14 (Sonoma) or later** (the app uses the Observation framework).
- **Xcode 15+** to build and run the app.
- The engine alone (`RenamerCore`) builds and tests with just the Swift
  toolchain — no Xcode app required.

## Run the app

Open `MediaRenamer/MediaRenamer.xcodeproj` in Xcode and press ⌘R. Preview is
read-only; only **Apply** touches disk, and it confirms first. Try it on a copy.

## Package a shareable build

```sh
./scripts/package-unsigned.sh   # -> build/MediaRenamer-unsigned.zip (universal, ad-hoc)
```

This needs no Apple Developer account. The app is **not notarised**, so on
another Mac the first launch is blocked by Gatekeeper — open it once with
**right-click → Open** (the script prints the exact steps). For a no-warning,
double-click experience, get a paid Developer ID and run `scripts/notarize.sh`
instead.

## Test the engine

The engine builds and tests with just the Swift toolchain (no Xcode app):

```sh
swift test --package-path RenamerCore
```

## Layout

```
RenamerCore/   Swift Package — the engine (pure logic, Foundation only). Headlessly testable.
MediaRenamer/  The SwiftUI app (Xcode project); depends on ../RenamerCore as a local package.
SPEC.md        Full specification + roadmap.
```

## Status

**Working app.** Pick a folder, preview, and Apply real renames — with
empty-folder cleanup and junk sent to the macOS Trash. The full walkthrough is in
the [Quick Start guide](https://deejaymorgan.github.io/media-renamer/). The engine
is covered by 105 tests, including a parity suite mirrored from the original
Python oracle.

Not built yet: undo UI, online title verification, and a *notarised* `.app`
(unsigned ad-hoc packaging works today — see above; see the roadmap in
[`SPEC.md`](SPEC.md)).

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2026 Daniel Morgan.

## Disclaimer

A personal project, shared as-is with **no support or warranty** and no promise
of updates. Issues and PRs are welcome but may not get a response. Always keep a
backup of media you care about before running bulk file operations.
