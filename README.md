# Media Renamer

A native **macOS (SwiftUI)** app that restructures a folder of `.mkv` files (and
subtitle sidecars) into a Plex/Jellyfin-friendly tree:

- **TV:** `Show Name/Season N/Show Name S##E##.mkv`
- **Movie:** `Movie Name (Year)/Movie Name (Year).mkv`

A ground-up Swift rebuild of an earlier Python CLI. The Python project
(`~/Dev/tv-show-renamer`) is kept only as the behavioural spec and test oracle —
no Python ships here. See [`SPEC.md`](SPEC.md) for the full plan.

## Layout

```
RenamerCore/      Swift Package — the engine (pure logic, no UI). Testable headlessly.
MediaRenamer/     (planned) the SwiftUI app, added once developed in Xcode.
SPEC.md           Full specification + roadmap.
```

## Status

Early. The engine's **parsing layer** is ported and parity-tested against the
Python oracle: classification, episode/year detection, title formatting, and
subtitle-language detection. Planning, conflict detection, junk handling,
execution, and the SwiftUI app are next (see the roadmap in `SPEC.md`).

## Developing & testing the engine

The engine needs only the Swift toolchain (no Xcode app) to build and test:

```sh
swift test --package-path RenamerCore
```

> First run requires the Xcode license to be accepted once:
> `sudo xcodebuild -license accept`

The SwiftUI app target (M2 onward) is built and previewed in **Xcode**.
