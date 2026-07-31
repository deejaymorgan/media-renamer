# Media Renamer

> **Note for human readers:** this file is build/architecture guidance for AI
> coding agents (e.g. Claude Code) working in this repo. It is *not* needed to
> use or build the app — see [`README.md`](README.md) for that.

Native **macOS (Swift + SwiftUI)** app that restructures a folder of `.mkv` files
(and subtitle sidecars) into a Plex/Jellyfin-friendly tree:
- TV: `Show Name/Season N/Show Name S##E##.mkv`
- Movie: `Movie Name (Year)/Movie Name (Year).mkv`

Two layouts, chosen per plan / per media kind / per item. The UI calls them
**Folders** and **Flat**; the engine's cases are `organise` and `renameOnly`.
Flat puts the identical filenames straight in the chosen folder with no tree,
and is the app's default at every launch (never persisted).

A ground-up Swift rebuild of an earlier Python CLI. That earlier project is
**only the behavioural spec + test oracle** — no Python ships here, and the app
never calls it. Swift tests mirror the Python `tests/` as the parity contract.

## Architecture
- **`RenamerCore/`** — the engine: a pure Swift Package (Foundation only, no UI,
  no prompts). Returns data; the app decides presentation and when to touch disk.
- **`MediaRenamer/`** — the SwiftUI app (Xcode project). Links `RenamerCore` as a
  local package (`../RenamerCore`). `AppModel` (`@Observable`) holds the `Plan`
  and re-plans on edits.

## Key Files
- `RenamerCore/Sources/RenamerCore/` — `Parser`/`Patterns`/`Constants` (parsing),
  `TitleFormatter`, `Sidecars`, `Scanner`, `PlanModel` (NodePlan/Plan/Operation/
  RenameUnit), `PlanBuilder` (build/replan/resolve), `ConflictChecker`,
  `QualityTag` (version labels for the resolver), `Executor` + `Trasher` (apply).
- `MediaRenamer/MediaRenamer/` — `ContentView` (split-view shell + apply bar +
  overrides indicator), `Sidebar` (rows + the layout chips), `Inspector`
  (editable fields, results, junk, conflict resolver — reports layout, doesn't
  set it), `OutputModeUI` (mode vocabulary/colour/glyph + `ModeChip`),
  `Palette` (colour legend), `AcronymBar`, `AppModel`.
- `SPEC.md` — full design + roadmap + known limitations. `README.md` — quickstart.

## Build / test / run
- Engine (no Xcode needed): `swift test --package-path RenamerCore`
- App: open `MediaRenamer/MediaRenamer.xcodeproj` in Xcode, ⌘R. Or build headless:
  `xcodebuild -project MediaRenamer/MediaRenamer.xcodeproj -scheme MediaRenamer -destination 'platform=macOS' build`
- Preview is read-only; only **Apply** touches disk (it confirms first). Use copies.

## Conventions
- Engine: Swift package `swift-tools 6.0`, **Foundation only**, no dependencies.
- App: `SWIFT_VERSION = 5.0`, **non-sandboxed** (`ENABLE_APP_SANDBOX = NO`),
  deployment target **macOS 14+** (uses the Observation framework).
- Primary video: `.mkv` only. Sidecars: `.srt .sub .idx .ass .ssa .vtt`.
- Junk = anything else, plus name patterns: `sample`, `screen(s)`, `proof`, `thumb(s)`
  — but **only on a node being renamed**. Skipped folders and already-named ones
  are out of contract: nothing inside them is counted, listed, or trashed.
  `NodePlan.junk` gates the stored `detectedJunk` on status, so consumers can't
  reopen the hole.
- Native Trash via `FileManager.trashItem` (`SystemTrasher`).
- Library folders (`movies/music/tv`) and hidden/metadata files (`.DS_Store`, `._*`) ignored.
- New parsing/planning/execution code lands with parity tests mirrored from the
  Python oracle; the quality-tag/resolver and junk-scope suites are new (the CLI
  only skips conflicts, and only ever prompted about junk in folders it was
  already processing).

Past lessons & decisions: LEARNINGS.md — skim before starting significant work.
