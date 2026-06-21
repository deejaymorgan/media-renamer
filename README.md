# Media Renamer

A native **macOS (SwiftUI)** app that restructures a folder of `.mkv` files (and
subtitle sidecars) into a Plex/Jellyfin-friendly tree:

- **TV:** `Show Name/Season N/Show Name S##E##.mkv`
- **Movie:** `Movie Name (Year)/Movie Name (Year).mkv`

A ground-up Swift rebuild of an earlier Python CLI. The Python project
(`~/Dev/tv-show-renamer`) is kept only as the behavioural spec and test oracle —
no Python ships here. See [`SPEC.md`](SPEC.md) for the full design and roadmap.

## Layout

```
RenamerCore/   Swift Package — the engine (pure logic, Foundation only). Headlessly testable.
MediaRenamer/  The SwiftUI app (Xcode project); depends on ../RenamerCore as a local package.
SPEC.md        Full specification + roadmap.
```

## Status

**Working app.** Pick a folder → preview the plan → edit titles, set acronym
casing, choose which junk to trash, resolve duplicate versions → **Apply**
(real renames + empty-folder cleanup + junk to the macOS Trash). The engine is
parity-tested against the Python oracle (91 tests).

Not built yet: undo UI, online title verification, and a *notarised* `.app`
(unsigned ad-hoc packaging works today — see below; see the roadmap in `SPEC.md`).

## Run the app

Open `MediaRenamer/MediaRenamer.xcodeproj` in Xcode and press ⌘R. Preview is
read-only; only **Apply** touches disk, and it confirms first. Try it on a copy.

## Package a shareable build

```sh
./scripts/package-unsigned.sh   # -> build/MediaRenamer-unsigned.zip (universal, ad-hoc)
```

This needs no Apple Developer account. The app is **not notarised**, so on
another Mac the first launch is blocked by Gatekeeper — open it once with
right-click → Open (the script prints the exact steps). For a no-warning,
double-click experience, get a paid Developer ID and run `scripts/notarize.sh`
instead.

## Test the engine

The engine builds and tests with just the Swift toolchain (no Xcode app):

```sh
swift test --package-path RenamerCore
```
