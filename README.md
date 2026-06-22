# Media Renamer

A native **macOS (SwiftUI)** app that restructures a folder of `.mkv` files (and
subtitle sidecars) into a Plex/Jellyfin-friendly tree:

- **TV:** `Show Name/Season N/Show Name S##E##.mkv`
- **Movie:** `Movie Name (Year)/Movie Name (Year).mkv`

Pick a folder → preview the plan → tweak titles, set acronym casing, choose which
junk to trash, resolve duplicate versions → **Apply**. Nothing on disk changes
until you press Apply, and it asks for confirmation first.

See [`SPEC.md`](SPEC.md) for the full design and roadmap.

## Screenshots & quick start

A step-by-step walkthrough with screenshots is in the
**[Quick Start guide](https://deejaymorgan.github.io/media-renamer/)**, rendered
via GitHub Pages.

## Download & run

Grab the latest build from the
[**Releases**](https://github.com/deejaymorgan/media-renamer/releases/latest) page:

1. Download **`MediaRenamer-<version>.dmg`** (or the `.zip`) from the release **Assets**.
2. Open the `.dmg` and **drag MediaRenamer into your Applications folder** (or, for
   the `.zip`, unzip it and move `MediaRenamer.app` to Applications).
3. **First launch only.** The app is *ad-hoc signed but not notarised* — it's a free
   project with no paid Apple Developer account — so macOS Gatekeeper blocks the very
   first open. Clear it **once** and it opens normally forever after. Pick whichever
   suits you (all assume the app is in `/Applications` — adjust the path otherwise):

   - **Easiest — any macOS, one Terminal line:**
     ```sh
     xattr -dr com.apple.quarantine /Applications/MediaRenamer.app
     ```
     Then double-click the app as usual — no prompts.
   - **No Terminal — macOS 15 Sequoia / macOS 26 Tahoe:** double-click the app once
     (it's blocked — click **Done**), then open **System Settings → Privacy &
     Security**, scroll to **Security**, and click **Open Anyway** next to the
     "_MediaRenamer was blocked…_" message. Authenticate, then click **Open**.
   - **No Terminal — macOS 14 Sonoma:** **Control-click (right-click) the app → Open
     → Open**. (Sonoma only, and don't double-click first — that path has no Open
     button.)

That's it — see the
[Quick Start guide](https://deejaymorgan.github.io/media-renamer/) to learn the
workflow.

> **Why the warning?** Notarising would remove it, but that requires a paid Apple
> Developer ID. The build is open-source and reproducible — you can also
> [build it yourself](#build-from-source).

## ⚠️ Safety

This app **renames and moves your files** and sends unwanted "junk" to the macOS
**Trash**. The preview is read-only — only **Apply** touches disk, and it confirms
first. Renaming never overwrites, and trashed files can be restored with Finder's
**Put Back** — but treat Apply as a real, bulk filesystem operation and
**run it on a copy of your media first**, until you trust the results.

Full safety notes are in the
[Quick Start guide](https://deejaymorgan.github.io/media-renamer/).

## Requirements

- **To use it:** **macOS 14 (Sonoma) or later** (the app uses the Observation
  framework). Just download a release (above).
- **To build it:** **Xcode 15+** for the app. The engine alone (`RenamerCore`)
  builds and tests with just the Swift toolchain — no Xcode app required.

## Build from source

Open `MediaRenamer/MediaRenamer.xcodeproj` in Xcode and press ⌘R. Preview is
read-only; only **Apply** touches disk, and it confirms first. Try it on a copy.

## Package a shareable build

```sh
./scripts/package-unsigned.sh   # -> build/MediaRenamer-unsigned.zip (universal, ad-hoc)
./scripts/make-dmg.sh           # -> build/MediaRenamer-<version>.dmg (drag-to-Applications)
```

This needs no Apple Developer account. The app is **not notarised**, so on
another Mac the first launch is blocked by Gatekeeper — recipients clear it once
(see [Download & run](#download--run) for the exact, current steps). For a
no-warning, double-click experience, get a paid Developer ID and run
`scripts/notarize.sh` instead.

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

Pick a folder, preview, and Apply real renames — with
empty-folder cleanup and junk sent to the macOS Trash. The full walkthrough is in
the [Quick Start guide](https://deejaymorgan.github.io/media-renamer/). The engine
is covered by 105 tests, including a regression suite that pins its parsing
and planning behaviour.

Not built yet: undo UI, online title verification, and a *notarised* `.app`
(unsigned ad-hoc packaging is available now — see above; see the roadmap in
[`SPEC.md`](SPEC.md)).

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2026 Daniel Morgan.

## Disclaimer

A personal project, shared as-is with **no support or warranty** and no promise
of updates. Issues and PRs are welcome but may not get a response. Always keep a
backup of media you care about before running bulk file operations.
