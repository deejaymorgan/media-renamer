# Media Renamer — Native macOS App Specification

**Status:** v1.0 shipped, extending · **Updated:** 2026-07-31 · **Behavioural
baseline:** an earlier (unpublished) Python engine (`renamer.py` + `data.py`)

A native macOS app that restructures a folder of `.mkv` files (and subtitle
sidecars) into a Plex/Jellyfin-friendly tree. A ground-up rebuild of an existing
Python CLI as a **SwiftUI** app on a **fresh Swift engine** — the Python project
is kept only as the behavioural specification (the rules) and test oracle.

Two output shapes, chosen per plan / per media kind / per item (§5, *Output modes*):

- **Folders** — `Show Name/Season N/Show Name S##E##.mkv`, `Movie Name (Year)/Movie Name (Year).mkv`
- **Flat** — the identical filenames, directly in the chosen folder, no folder tree

*Folders* and *Flat* are what the UI calls them, everywhere. The engine's cases
are `organise` and `renameOnly` — API names, not display names, and deliberately
unchanged.

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
- Shippable as a `.app`. **✅ unsigned build shipped** (notarised double-click-clean still to come).

### Non-Goals
- Cross-platform support. **macOS only** — we lean on Foundation, the real
  Trash, and SwiftUI.
- Multi-user / sharing / cloud sync. A single-user desktop tool.
- Changing the renaming rules. Naming conventions, parsing, and output formats
  stay as specified by the Python baseline (the duplicate *resolver* and the
  rename-only *output mode* are new front-end capabilities layered on top —
  neither changes how a single file is parsed or named; rename-only produces
  byte-identical filenames and only omits the folders around them).
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
      OutputMode.swift              # OutputMode / ModeOverride / ModeCascade (new — no oracle)
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
    Tests/RenamerCoreTests/         # swift test — mirrors the Python oracle (140 tests, 17 suites)
  MediaRenamer/
    MediaRenamer.xcodeproj          # app target; links ../RenamerCore as a local package
    MediaRenamer/
      MediaRenamerApp.swift         # @main App
      AppModel.swift                # @Observable document model (choose/replan/resolve/apply)
      ContentView.swift             # NavigationSplitView shell + toolbar + bottom apply bar
      Sidebar.swift                 # source list (All / TV / Movies / Unchanged / Skipped) + layout marks/menus + flag badges
      Inspector.swift               # detail: editable fields, results, junk toggles, conflict resolver
      AcronymBar.swift              # acronym keep/Title chips
      OutputModeUI.swift            # mode vocabulary/colour/glyph, the layout chip/badge/picker, global picker
      Palette.swift                 # colour legend (categories + the two layout tints)
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
| Settings | `UserDefaults` (acronym modes persisted; the **output mode deliberately is not** — see §5) |
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
  (`sample/screens/proof/thumbs`) → offered for deletion to Trash — but **only
  inside a node that is being renamed**. A folder the app skipped (no videos,
  mixed content, nothing parsable), and one that already has the name it wants,
  are both out of contract: the app is not restructuring them, so it never
  counts, lists, or trashes anything inside them. The rule is enforced on the
  model — `NodePlan.junk` gates the raw scan result on status — so every
  consumer inherits it rather than each one remembering to filter.
  Approved junk is still trashed when the node's own moves then skip on a
  conflict: junk approval is its own axis, and every file was listed with a
  checkbox.
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
- **Output modes (new — beyond the CLI; the CLI always built folders):** every
  node carries a resolved `outputMode`, stamped once at build time from a
  three-level cascade — **item → group ("all TV" / "all Movies") → global**,
  nearest explicit setting winning. `organise` is the tree above; `renameOnly`
  puts the **identical filename** directly in the chosen root and builds nothing.
  Only the containing path differs: `computeDestination` composes the name once
  and both branches place that one string, which is why **flattening creates no
  new class of collision** — the destination folder never disambiguates anything
  the filename doesn't already carry (for TV the season folder is derived from the
  episode code in the name; for movies the folder *is* the name's stem). One
  resolver, one conflict checker, both modes. A single plan may hold both shapes
  at once. Files inside subfolders are lifted to the root and every vacated
  directory is offered for removal, deepest first (`Executor` removes only a
  genuinely empty one). One override per show, never per season — flattening
  collapses the seasons into the same folder anyway.
  - **Rename-only is the app's default at every launch and is deliberately never
    persisted**; the engine's own default stays `organise` so non-UI call sites
    are unchanged. Group and item overrides reset when a new folder is chosen but
    **survive an Apply** — the only edit layer that does — because applying in
    several passes over one staging folder is the workflow they serve.
  - Because the default flattens, the active mode is stated in the toolbar, on
    **any sidebar row whose layout differs from the toolbar's**, on each preview
    group's destination band, and in the confirmation dialog (which also counts
    the source folders that will disappear) — with **equal weight in both
    directions**, so neither mode is the one you click through. The toolbar
    states the global mode permanently and never scrolls, so a row only has to
    speak when it is an exception to it: when it pins a mode of its own, or when
    its group does. A plan with no overrides carries no row marks at all, and you
    still cannot apply the wrong mode without being told.
  - **Invariant — suppressing row marks is only safe while the toolbar picker
    cannot disappear.** The rule above hides a row's mark whenever the row agrees
    with the global layout (`AppModel.statesOwnLayout`), which spends the row's
    silence on the toolbar's permanence: if the picker ever stopped being on
    screen, a plan with no overrides would state its layout *nowhere*. Two
    numbers in `ContentView` are what guarantee it, and they are load-bearing for
    layout visibility rather than cosmetic tuning. The sidebar column is capped
    at **half the window width**, which caps a split position that otherwise
    persists across launches, so the detail region can never be dragged narrow
    enough for the trailing `.primaryAction` items — the picker among them — to
    collapse into a `»` overflow menu. Half is what makes the bound
    self-maintaining rather than a number that has to be re-tuned: measured, both
    trailing items need roughly `sidebar + 510` points, so a sidebar of `W/2` is
    safe for every `W ≥ 1020`, at any window size and with no per-width
    arithmetic. The window's `minWidth: 1160` then holds the window above that
    floor with headroom for the toolbar's own content — restoring the longer
    `Organise / Rename only` labels costs 68pt of intrinsic width, making the
    requirement `W ≥ 1156`, which at 1020 would have reintroduced the overflow
    invisibly. Loosen either bound and the marks stop being an exception system.
  - The three levels: toolbar for the whole plan,
    section header for a media kind, and — for one item — the **row's context
    menu**, mirrored as **View ▸ Layout** on the selection (a season row's menu
    targets its parent show, since layout is show-scoped). The row itself carries
    a passive mark, not a control: a row shows state, and a three-way setting on
    every row would be a control below the HIG's 20×20pt minimum sitting
    unannounced among the `dup`/junk/verify status badges. Headers draw glyph +
    word + chevron and act as the legend; row marks draw the **glyph alone**, so
    both modes are one width and every mark shares one left and one right edge.
    The pinned-vs-inheriting distinction (bordered and filled vs a soft wash)
    holds on both. The inspector reports the resolved mode and does not set it —
    the cascade reads as one setting at three scopes rather than two panes' worth
    of settings.
  - Overrides are easy to lose track of (they survive an Apply, and an emptied
    group keeps its section on screen just to stay reachable), so the toolbar
    carries an **overrides count and a Reset All**, mirrored in the View menu.

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
- **Junk → Trash** checkboxes, on the items being renamed.
- **Apply:** real renames + empty-source cleanup + junk to the Trash, behind a
  confirm dialog, with a result summary; the folder re-scans afterward.
- **Duplicate-version resolver** (beyond the original MVP scope).
- **Layout modes:** Folders vs Flat, with a three-level cascade
  (toolbar / section header / row context menu, mirrored as View ▸ Layout), an
  overrides count and Reset All beside the toolbar picker, a root-anchored
  destination band on every preview group, and a mode-naming confirm dialog.

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
- **Skipped on-disk items aren't in the conflict index.** `ConflictChecker` keys
  on the destinations the *plan* carries — move targets plus in-place units — so
  an item the plan skipped (a loose non-video file, an unrecognised folder) that
  already occupies a destination path is not flagged. The preview shows the
  rename; `Executor` then refuses to overwrite, skips that one file, and reports
  *"Skipped (target exists)"* in the result summary. Nothing is lost, but the
  preview was optimistic and the resolver isn't offered. Pre-existing and
  mode-independent — verified in both modes — though **rename-only widens it**,
  because every flat destination lands in the root, which is exactly where loose
  skipped files accumulate. A fix means indexing non-planned residents *and*
  giving the resolver a way to label a file it isn't renaming; that is a
  conflict-system change, deliberately not made alongside the output modes.
- **Cleanup only follows files that move.** An emptied source folder (and every
  directory a moved file is lifted out of) is offered for removal, deepest first.
  A subdirectory that no planned file leaves — one holding only junk, or only
  skipped files — is not, so trashing its contents can leave an empty directory
  behind, which in turn keeps its parent. This is now confined to subdirectories
  *inside a renaming node*: a skipped folder's contents are never trashed, so it
  cannot be emptied and left behind in the first place. `Executor` only ever removes a
  genuinely empty directory, so this is litter rather than risk, and it keeps the
  confirmation dialog's folder count from overstating what will actually go.
- **macOS 26 chrome.** Resolved. The summary counts moved out of the toolbar
  into colour-coded chips in the bottom bar, and the acronym bar now sits at the
  **bottom** too — a divider-separated strip immediately above the apply bar. It
  was briefly a real title-bar accessory (`NSTitlebarAccessoryViewController`),
  to keep the inspector title clear of it on the first layout; a bottom sibling
  sidesteps the SwiftUI sibling-bar + `NavigationSplitView` safe-area bug
  (`rdar://122947424`) that forced that hack, so the accessory plumbing is gone.

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
| **M5.7 — Output modes** | ✅ rename-only (flat) alongside organise, chosen per plan / per media kind / per item; mode surfaced in the toolbar, on the rows that differ from it, on preview bands, and in the confirm dialog |
| **M5.8 — Junk scope + layout UX** | ✅ junk confined to nodes being renamed (safety fix); layout as one control at three scopes — toolbar, section header, and the row's context menu mirrored in View ▸ Layout — with rows carrying a passive mark; Folders/Flat vocabulary; a colour and glyph per mode; overrides count + Reset All; root-anchored destination bands with path/reveal |
| **M5.9 — Layout chips + close-out** | ✅ bottom-bar layout chips — the plan's shape as item counts, glyph + word + tint single-sourced from the mode vocabulary; layout-discoverability inquiry closed (2026-08-01: pairing stays hover-taught, no further teaching surface); the stale menu-named row-layout type renamed to `ItemLayoutPicker`; committed fixture script `scripts/make-scratch.sh` + one recorded end-to-end Apply |
| **M5.10 — Toolbar truth + quiet chips** | ✅ overrides count de-glassed — status off the glass, reset alone on it (WWDC25 310); per-segment layout tooltips unmasked (one `.help` per control); inherited group chips quiet monochrome, tint reserved for a pinned override; header trailing rhythm measured (14pt) and fixed; the group rung mirrored in View ▸ Layout and the header's right-click |
| **M6 — Undo** | ⬜ reverse the last applied batch (engine records moves; UI pending) |
| **M7 — Online verify** | ⬜ opt-in TMDb/TVDB confirmation + cache |
| **M8 — Package** | ⬜ notarised `.app`, app icon, double-click launch |
| **— Idempotent re-scan** | ✅ parser preserves our ` - <label>` version tails, so re-scanning resolved files is a no-op |

Parity with the old CLI was reached at **M4**; everything after is new capability.

**After 1.3.0:** the fix-and-hardening work from the post-release code review
(CI, Trash defaults, organised-library detection, parsing, state across Apply,
performance, docs) is tracked in
[#11 — Roadmap after 1.3.0](https://github.com/deejaymorgan/media-renamer/issues/11),
one issue per step, in recommended order.

---

## 8. Data Model (engine)

- `MediaType` — `.tv / .movie / .unknown`.
- `MediaParse` — parsed fields (title, episode code, season, preserved stopwords).
- `OutputMode` — `.organise / .renameOnly`, the layout a node's files land in.
- `ModeOverride` — `.inherit / .organise / .renameOnly`; `forced` is the single
  place `inherit` becomes a decision.
- `ModeCascade` — `global` + `tv`/`movies` group overrides + per-source `items`;
  `mode(for:mediaType:)` resolves one node. Stored by the app, resolved by the
  engine.
- `NodePlan` — one top-level entry's plan: `source`, `mediaType`, `status`
  (`.rename / .unchanged / .skip`), `operations`, `junk` (a status gate over the
  stored `detectedJunk`: empty unless the node is `.rename`, so junk can only
  ever come from something being restructured), `previewPairs`,
  verify info, the editable `editTitle`/`editYear`, `units`, and the resolved
  `outputMode` (everything downstream reads this one field rather than
  re-resolving three settings).
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
  (no Xcode, no display) — **140 tests across 17 suites**, the parity contract for
  every rule.
- New parsing/planning/execution code lands with mirrored cases from the Python
  `tests/test_renamer.py` oracle. The quality-tag, duplicate-resolve,
  output-mode and junk-scope suites are **new** (no oracle — the Python CLI only
  detects and skips conflicts, always built folders, and only ever prompted
  about junk in folders it was already processing).
- `JunkScopeTests` pins the junk rule end to end: skipped and unchanged nodes
  contribute nothing to the count or the trash list, junk returns when a layout
  change gives a node work again, and applying a plan leaves a skipped folder's
  contents byte-for-byte alone.
- The four output-mode suites are `FlatDestinationTests` (the flat shape, and
  that the filename is byte-identical in both modes), `ModeCascadeTests` (pure
  item → group → global resolution), `ModeEquivalenceTests` (the conflicted-source
  set is identical under both modes across a fixture table — the property the
  design rests on) and `ModeReplayTests` (the mode composes with acronyms,
  labels and title edits, and survives a rebuild).
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
