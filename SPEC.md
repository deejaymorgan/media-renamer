# Media Renamer — Native macOS App Specification

**Status:** MVP delivered, extending · **Updated:** 2026-05-31 · **Behavioural
baseline:** an earlier (unpublished) Python engine (`renamer.py` + `data.py`)

A native macOS app that restructures a folder of `.mkv` files (and subtitle
sidecars) into a Plex/Jellyfin-friendly tree. A ground-up rebuild of an existing
Python CLI as a **SwiftUI** app on a **fresh Swift engine** — the Python project
is kept only as the behavioural specification (the rules) and test oracle.

- **TV:** `Show Name/Season N/Show Name S##E##.mkv`
- **Movie:** `Movie Name (Year)/Movie Name (Year).mkv`

---

## 1. Vision

One Swift engine, one SwiftUI front-end, fully native, macOS-only.

- **Engine (`RenamerCore`):** a pure Swift Package — parsing, classification,
  planning, conflict detection, execution. No UI, no I/O prompts. Fully unit-
  tested via `swift test` (no Xcode required to test the engine).
- **App (`MediaRenamer`):** a SwiftUI macOS app that depends on `RenamerCore`
  and renders/drives it. The engine is never re-implemented outside Swift.
- **Heritage:** the earlier (unpublished) Python CLI defines the *rules*
  (formatting syntax, year/episode parsing, duplicate checking, sidecar/junk
  handling). Its `tests/` are the parity oracle the Swift tests mirror. No Python
  code ships here.

### Why a fresh engine
The Python engine is CLI-shaped: it prompts mid-logic, prints its preview, plans
in one shot, and holds no state. A GUI needs the opposite — a pure core that
returns data, a mutable document model that re-plans on edits, commands that can
undo, and async operations that don't block the UI. That's an architecture
change best made as a clean rebuild, in the language the UI uses.

---

## 2. Goals & Non-Goals

### Goals
- A native macOS GUI matching the original CLI's behaviour. **✅ parity reached.**
- Editable titles before apply. **✅ delivered.**
- Remembered settings (recent acronym choices). **✅ acronyms persisted.**
- Remaining north-star: **online title verification**, **undo last run**.
- A clean engine/UI split, with the engine pure and headlessly testable. **✅**
- Shippable as a double-click `.app` (eventually).

### Non-Goals
- Cross-platform support. **macOS only** — we lean on Foundation, the real
  Trash, and SwiftUI.
- Multi-user / sharing / public release. Personal tool.
- Changing the renaming rules. Naming conventions, parsing, and output formats
  stay as specified by the Python baseline (the duplicate *resolver* is a new
  front-end capability layered on top — it does not change how a single file is
  parsed or named).
- Re-implementing logic outside Swift (no JS/Python port — a single source of
  truth avoids parsing drift).

---

## 3. Architecture

### Repo layout (actual)
```
media-renamer/
  RenamerCore/                      # the engine — pure Swift Package, no UI
    Package.swift                   # swift-tools 6.0, .macOS(.v13), library RenamerCore
    Sources/RenamerCore/
      Constants.swift               # ported data tables (ext, tokens, langs, junk patterns)
      Patterns.swift                # compiled NSRegularExpressions + match helpers
      StringHelpers.swift           # Python-parity string ops (splitext, rstrip, …)
      MediaParse.swift              # MediaType, MediaParse
      TitleFormatter.swift          # title-case / normalise / preservedStopwords
      Parser.swift                  # classify / releaseYear / tv / movie
      Sidecars.swift                # subtitle language suffix + sidecar grouping
      Scanner.swift                 # one-level directory scan → (videos, sidecars, junk)
      PlanModel.swift               # NodePlan, Plan, Operation, RenameUnit, PreviewPair
      PlanBuilder.swift             # build / replan / resolve  (plan_input_dir port + edits)
      ConflictChecker.swift         # duplicate-target detection
      QualityTag.swift              # version-label parsing for the resolver (new — no oracle)
      Executor.swift                # apply moves + empty-dir cleanup; ApplyResult
      Trasher.swift                 # Trasher protocol + SystemTrasher (real macOS Trash)
    Tests/RenamerCoreTests/         # swift test — mirrors the Python oracle (91 tests, 11 suites)
  MediaRenamer/
    MediaRenamer.xcodeproj          # app target; links ../RenamerCore as a local package
    MediaRenamer/
      MediaRenamerApp.swift         # @main App
      AppModel.swift                # @Observable document model (choose/replan/resolve/apply)
      ContentView.swift             # NavigationSplitView shell + toolbar + bottom apply bar
      Sidebar.swift                 # source list (All / TV / Movies / Unchanged / Skipped) + flag badges
      Inspector.swift               # detail: editable fields, results, junk toggles, conflict resolver
      AcronymBar.swift              # acronym keep/Title chips
      Assets.xcassets
  SPEC.md  README.md  .gitignore
```

### UI shape
A `NavigationSplitView`: a **sidebar** lists the plan grouped into All items /
TV / Movies / Unchanged / Skipped, each row flagged for duplicate / junk /
verify. A multi-season show is one row that **expands into a Show → Season tree**
(with Expand-all / Collapse-all): selecting the show edits/acts on every season,
selecting a season focuses just that one. The **detail inspector** shows the
selected item (or an "All" mode of collapsible, individually-editable cards). The
inspector edits the title (and, for movies, the year), lists the resulting files
(grouped by season for TV), offers per-file junk→Trash checkboxes, and — for a
duplicate target — an interactive resolver. An acronym bar (keep vs Title-case
chips) appears when all-caps words are detected; a bottom bar applies the plan
behind a confirmation dialog.

### Principles
- **Engine is pure & dependency-free** (Foundation only). It returns data; the
  app decides how to present it and when to touch disk. No prompts, no printing.
- **A document model drives the UI.** `AppModel` (`@Observable`) holds the
  `Plan`; editing a title/year re-computes that node's destinations and re-runs
  conflict detection live. Acronym choices and duplicate resolutions are kept and
  re-applied across rebuilds.
- **Operations are recorded for undo.** `Executor` returns
  `ApplyResult.completedMoves`; the undo *engine hook* exists, the undo *UI* is
  not built yet (M6).
- **Async off the main actor — planned.** Apply runs synchronously (fine for
  typical folders); moving it off-main is a TODO for very large trees.

### Native wins we take for free
- `FileManager.trashItem(at:resultingItemURL:)` — real macOS Trash, with the
  system's own **"Put Back"** (partial undo from day one).
- `.fileImporter` — native folder picker.
- Automatic light/dark appearance, real OS integration, Xcode Previews as the
  design loop.
- Swift concurrency (`async`/`await`, actors) available for background work.

---

## 4. Tech Stack

| Concern | Choice |
|---|---|
| Toolchain | Swift 6.x (Xcode) |
| Engine | `RenamerCore` Swift Package — `swift-tools 6.0`, Foundation only |
| App language mode | `SWIFT_VERSION = 5.0` (app target); engine uses tools 6.0 |
| UI | SwiftUI |
| Min OS | Engine package: macOS 13+. App deployment target: **macOS 14.0** (`MACOSX_DEPLOYMENT_TARGET = 14.0`, required by the Observation framework) |
| Tests | Swift Testing (`swift test`) — engine only, no Xcode needed |
| Trash | `FileManager.trashItem` (via `SystemTrasher`) |
| Settings | `UserDefaults` (acronym modes persisted) |
| Online lookup (goal) | TMDb/TVDB REST + local cache (opt-in) |
| Packaging (later) | Xcode → notarised `.app` |
| Sandbox | **Off** (`ENABLE_APP_SANDBOX = NO`) for personal use; revisit for App Store |

---

## 5. The Rules (ported from the Python baseline)

Verbatim behaviour from the earlier Python engine, pinned by parity tests:

- **Classification:** episode code → TV; else release year → movie; else skipped.
- **Episode codes:** `S01E01`, `S01E01E02`, `S01E01-E02`, 4-digit seasons
  (`S2024E01` → `Season 2024`), any casing → uppercased.
- **Year detection:** canonical `Title (YYYY)` wins; else rightmost scene-style
  `.YYYY.<known metadata token>`; else rightmost non-leading year. Avoids
  year-in-title traps.
- **Title formatting:** dots→spaces, `:`→` - `, hyphens preserved, Chicago/AP
  title-case with mid-title stopwords lowercased (explicit source capitals kept
  and flagged for verification), acronym map applied.
- **Movies:** `Title (Year)`; AKA keeps the English (right) side.
- **Sidecars:** `.srt/.sub/.idx/.ass/.ssa/.vtt` renamed alongside the video,
  preserving recognised language codes; unknown tokens dropped.
- **Junk:** anything not video/subtitle, plus name patterns
  (`sample/screens/proof/thumbs`) → offered for deletion to Trash.
- **Conflicts:** multiple sources → one destination are flagged. The original
  CLI only *skips* them; this app adds a **resolver** — keep them all by giving
  each a **version label** (parsed from quality: `2160p Remux`, `1080p WEB-DL`,
  edition cuts) rendered as `Title (Year) - 2160p.mkv` in one shared folder
  (Plex/Jellyfin "versions"). Unresolved conflicts are skipped at apply;
  existing-on-disk targets are skipped.
- **Loose-file grouping (new — beyond the CLI):** loose files at the root that
  share a show (TV) or title+year (movie) collapse into one node, the way a
  subfolder of the same files already does — so scattered episodes of a show land
  together. Grouping is **per show** for TV; a show's seasons are split at the
  destination (`Season N/`) and surfaced in the sidebar as a **Show → Season
  tree** rather than as separate nodes. When the root *also* holds a subfolder for
  that same show/movie, the loose files fold into **its** node instead (a
  subfolder represents the whole show, so a stray file of any season joins it).
  Two loose copies of one title group together and still surface as a duplicate
  for the version-label resolver.
- **Library folders** (`Movies/Music/TV`) and hidden/metadata files are ignored.

**Status:** the engine and the app are both built. The app delivers preview,
editable titles/years, acronym casing, junk→Trash, real apply (moves +
empty-folder cleanup + Trash), and duplicate-version resolution.

---

## 6. MVP — Delivered

The MVP — **pick a folder → see the plan → apply it** — is built, plus several
features beyond the original MVP line:

- Folder picker (`.fileImporter`), one-level scan.
- Sidebar + inspector preview: TV / Movies / Unchanged / Skipped, before→after,
  flag badges (duplicate / junk / verify), summary counts.
- **Editable titles** (+ movie year) with live re-plan.
- **Acronym** keep/Title chips, remembered across launches.
- **Junk → Trash** checkboxes.
- **Apply:** real renames + empty-source cleanup + junk to the Trash, behind a
  confirm dialog, with a result summary; the folder re-scans afterward.
- **Duplicate-version resolver** (beyond the original MVP scope).

Not yet: undo UI, online verification, a broader settings surface, packaging.

The engine is **idempotent**: it recognises its own `Title (Year) - <label>` output
(the parser preserves a ` - <label>` version tail after a canonical year, and
sidecars inherit their video's label), so re-scanning an already-organised folder
is a no-op rather than a re-flagged conflict.

### Known limitations
- **Synchronous apply.** Fine for typical folders; large trees would benefit from
  moving the work off the main actor.
- **Resolver + in-folder sidecars.** When multiple versions *and* their subtitle
  sidecars live in one folder, the resolver lists each colliding file separately
  on first resolve; the labelled output is correct and re-scans cleanly, but the
  first pass is more manual than the common loose-file case.
- **Loose sidecars aren't grouped.** Loose-file grouping collects videos only; a
  subtitle sitting loose at the root (not inside a folder) is still listed as an
  individual skipped entry rather than following its grouped video.
- **macOS 26 chrome.** Resolved. The summary counts moved out of the toolbar
  into colour-coded chips in the bottom bar, and the acronym bar is now a real
  title-bar accessory (`NSTitlebarAccessoryViewController`) so the inspector
  title clears it correctly on the first layout (the SwiftUI sibling-bar +
  `NavigationSplitView` safe-area bug, `rdar://122947424`, no longer applies).

---

## 7. Roadmap

| Milestone | State |
|---|---|
| **M0 — Parsing core** | ✅ `RenamerCore` parsing/formatting/sidecar rules, parity-tested |
| **M1 — Plan model** | ✅ folder scan, `PlanBuilder`, `ConflictChecker` — parity-tested |
| **M2 — Preview UI** | ✅ SwiftUI split-view: pick folder → preview |
| **M3 — Apply** | ✅ `Executor` + `Trasher`; Apply button, confirm dialog, result summary |
| **M4 — Junk + acronyms** | ✅ junk checkboxes + acronym chips — **CLI parity reached here** |
| **M5 — Editable titles** | ✅ live re-plan on title/year edits; acronyms remembered |
| **M5.5 — Duplicate resolver** | ✅ version-label resolution (new capability beyond the CLI) |
| **M5.6 — Loose-file grouping** | ✅ scattered same-show (and movie-version) loose files group like a subfolder; merge into a matching subfolder; seasons shown as a sidebar Show → Season tree |
| **M6 — Undo** | ⬜ reverse the last applied batch (engine records moves; UI pending) |
| **M7 — Online verify** | ⬜ opt-in TMDb/TVDB confirmation + cache |
| **M8 — Package** | ⬜ notarised `.app`, app icon, double-click launch |
| **— Idempotent re-scan** | ✅ parser preserves our ` - <label>` version tails, so re-scanning resolved files is a no-op |

Parity with the old CLI was reached at **M4**; everything after is new capability.

---

## 8. Data Model (engine)

- `MediaType` — `.tv / .movie / .unknown`.
- `MediaParse` — parsed fields (title, episode code, season, preserved stopwords).
- `NodePlan` — one top-level entry's plan: `source`, `mediaType`, `status`
  (`.rename / .unchanged / .skip`), `operations`, `junk`, `previewPairs`,
  verify info, the editable `editTitle`/`editYear`, and `units`.
- `RenameUnit` — one output file (a video or one of its sidecars): `episodeCode`,
  `season`, `languageSuffix`, `ext`, and `disambiguationSuffix` (the resolver's
  version label). Carries just enough to recompute its destination on an edit.
- `Operation` — `.move(from:to:)` / `.removeEmptyDirectory(_:)`; the unit of
  apply (and a future undo).
- `Plan` — `root` + `nodes` + `conflicts`; `conflictGroups` /
  `conflictGroup(containing:)` expose colliding sets to the UI.
- `ApplyResult` — moved / conflict / error / trashed counts, `completedMoves`
  (undo groundwork), and human-readable messages.

Execution always goes through the engine, so any future second front-end applies
changes through identical code.

---

## 9. Testing

- `swift test --package-path RenamerCore` runs the engine suite headlessly
  (no Xcode, no display) — **91 tests across 11 suites**, the parity contract for
  every rule.
- New parsing/planning/execution code lands with mirrored cases from the Python
  `tests/test_renamer.py` oracle. The quality-tag and duplicate-resolve suites
  are **new** (no oracle — the Python CLI only detects and skips conflicts).
- SwiftUI views stay thin; logic lives in the testable engine. UI tests are
  post-MVP.

---

## 10. Open Decisions

1. ~~App project layout.~~ **Resolved:** an Xcode project under `MediaRenamer/`
   references `../RenamerCore` via a local Swift-package path.
2. **Online verification provider** — TMDb vs TVDB; API-key storage (Keychain).
   Deferred to M7.
3. **Undo depth** — last run only (recommended) vs a multi-step history.
4. **Settings surface** — `UserDefaults` for now (acronyms persisted); revisit if
   it grows.
5. ~~App deployment target.~~ **Resolved:** set to **macOS 14.0**
   (`MACOSX_DEPLOYMENT_TARGET = 14.0`), the floor for the Observation framework.
   Raise the floor only if a newer-only API is adopted.
