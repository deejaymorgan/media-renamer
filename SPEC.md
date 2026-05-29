# Media Renamer — Native macOS App Specification

**Status:** Draft · **Date:** 2026-05-30 · **Behavioural baseline:** the original
Python engine at `~/Dev/tv-show-renamer` (`renamer.py` + `data.py`)

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
- **App:** a SwiftUI macOS app that depends on `RenamerCore` and renders/drives
  it. The engine is never re-implemented outside Swift.
- **Heritage:** the Python CLI (`~/Dev/tv-show-renamer`) defines the *rules*
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
- A native macOS GUI reaching full parity with the original CLI's behaviour.
- North-star features: **editable titles before apply**, **online title
  verification**, **undo last run**, **remembered settings**.
- A clean engine/UI split, with the engine pure and headlessly testable.
- Shippable as a double-click `.app` (eventually).

### Non-Goals
- Cross-platform support. **macOS only** — we lean on Foundation, the real
  Trash, and SwiftUI.
- Multi-user / sharing / public release. Personal tool.
- Changing the renaming rules. Naming conventions, parsing, and output formats
  stay as specified by the Python baseline.
- Re-implementing logic outside Swift (no JS/Python port — the drift trap the
  predecessor fell into).

---

## 3. Architecture

### Repo layout
```
media-renamer/
  RenamerCore/                 # the engine — pure Swift Package, no UI
    Package.swift
    Sources/RenamerCore/
      Constants.swift          # ported data tables (ext, tokens, langs, …)
      Patterns.swift           # compiled regexes + helpers
      StringHelpers.swift      # Python-parity string ops (splitext, rstrip, …)
      MediaParse.swift         # MediaType, MediaParse
      TitleFormatter.swift     # titleCase / normalise / preservedStopwords
      Parser.swift             # classify / releaseYear / tv / movie
      Sidecars.swift           # language suffix detection + sidecar naming
      (planned) PlanBuilder.swift, ConflictChecker.swift,
                RenamePlan.swift (document model), Executor.swift, Trasher.swift
    Tests/RenamerCoreTests/    # swift test — mirrors the Python oracle
  MediaRenamer.xcodeproj       # (planned) the SwiftUI app, added with Xcode
  MediaRenamer/                # (planned) app sources; depends on ../RenamerCore
  SPEC.md  README.md  .gitignore
```

### Principles
- **Engine is pure & dependency-free** (Foundation only). It returns data; the
  app decides how to present it and when to touch disk. No prompts, no printing.
- **A document model drives the UI.** Loading a folder yields a `RenamePlan` of
  editable entries (`@Observable`); editing a title re-computes that entry's
  destination and re-runs conflict detection.
- **Operations are reversible.** Each move/mkdir/trash is recorded so the last
  run can be undone.
- **Async, off the main actor.** Scans, applies, and (later) online lookups run
  as cancellable `async` work; the window stays responsive.

### Native wins we take for free
- `FileManager.trashItem(at:resultingItemURL:)` — real macOS Trash, with the
  system's own **"Put Back"** (partial undo from day one).
- `.fileImporter` — native folder picker.
- Automatic light/dark appearance, real OS integration, Xcode Previews as the
  design loop.
- Swift concurrency (`async`/`await`, actors) for background work.

---

## 4. Tech Stack

| Concern | Choice |
|---|---|
| Language | Swift 6 |
| Engine | `RenamerCore` Swift Package (Foundation only) |
| UI | SwiftUI (macOS 13+) |
| Tests | Swift Testing (`swift test`) — engine only, no Xcode needed |
| Trash | `FileManager.trashItem` |
| Settings | `UserDefaults` / `@AppStorage` |
| Online lookup (goal) | TMDb/TVDB REST + local cache (opt-in) |
| Packaging (later) | Xcode → notarised `.app` |
| Sandbox | **Off** for now (personal use); revisit only for App Store |

---

## 5. The Rules (ported from the Python baseline)

Verbatim behaviour from `~/Dev/tv-show-renamer`, pinned by parity tests:

- **Classification:** episode code → TV; else release year → movie; else skipped.
- **Episode codes:** `S01E01`, `S01E01E02`, `S01E01-E02`, 4-digit seasons
  (`S2024E01` → `Season 2024`), any casing → uppercased.
- **Year detection:** canonical `Title (YYYY)` wins; else rightmost scene-style
  `.YYYY.<known metadata token>`; else rightmost non-leading year. Avoids
  year-in-title traps (`2001 A Space Odyssey 1968…` → 1968).
- **Title formatting:** dots→spaces, `:`→` - `, hyphens preserved, Chicago/AP
  title-case with mid-title stopwords lowercased (explicit source capitals kept
  and flagged), acronym map applied.
- **Movies:** `Title (Year)`; AKA keeps the English (right) side.
- **Sidecars:** `.srt/.sub/.idx/.ass/.ssa/.vtt` renamed alongside the video,
  preserving recognised language codes; unknown tokens dropped.
- **Junk:** anything not video/subtitle, plus name patterns
  (`sample/screens/proof/thumbs`) → offered for deletion to Trash.
- **Conflicts:** multiple sources → one destination are all skipped & flagged;
  existing-on-disk targets are skipped.
- **Library folders** (`Movies/Music/TV`) and hidden/metadata files are ignored.

**Status:** the engine is **MVP-complete and parity-tested** (`RenamerCore`):
parsing/formatting, year & episode detection, sidecar language handling,
planning, conflict detection, and execution (apply moves + `rmdir`-empty +
native Trash). The remaining MVP work is the SwiftUI app — preview + apply
button — built in Xcode. Junk *detection* is done; the junk *panel* is M4.

---

## 6. MVP

**Pick a folder → see the plan → apply it.** The smallest genuinely useful app.

- Folder picker (`.fileImporter`), scan one level deep.
- Build & render the plan read-only: TV / Movies / Unchanged / Skipped /
  Titles-to-verify, before→after, conflict flags, summary counts.
- **Apply:** perform the renames; send junk to Trash; show a result log. Confirm
  dialog before applying. (Default acronym handling; no chips yet.)

Out of MVP: acronym chips, editable titles, undo UI, online verification,
settings, packaging.

---

## 7. Roadmap

| Milestone | Adds |
|---|---|
| **M0 — Parsing core** ✅ | `RenamerCore` parsing/formatting/sidecar rules, parity-tested |
| **M1 — Plan model** ✅ | Folder scan, `PlanBuilder`, `ConflictChecker` — all parity-tested |
| **M2 — Preview UI** | SwiftUI app: pick folder → read-only preview (needs Xcode) |
| **M3 — Apply** | engine ✅ (`Executor` + `Trasher`, conflict/exists skipping, tested); Apply button + result log (UI) pending |
| **M4 — Junk + acronyms** | Junk panel (checkboxes → Trash); acronym toggle chips (full CLI parity reached here) |
| **M5 — Quality of life** | Editable titles before apply; remembered settings (recent folders, acronyms) |
| **M6 — Undo** | Reverse the last applied batch in one action |
| **M7 — Online verify** | Opt-in TMDb/TVDB confirmation + cache |
| **M8 — Package** | Notarised `.app`, app icon, double-click launch |

Parity with the old CLI is reached at **M4**; everything after is new capability.

---

## 8. Data Model (engine)

- `MediaType` — `.tv / .movie / .unknown`.
- `MediaParse` — parsed fields (title, episode code, season, preserved stopwords).
- *(planned)* `RenameEntry` — a source URL + parse + computed destination +
  status + conflict flag; editable.
- *(planned)* `RenamePlan` — `@Observable` collection of entries; re-plans on
  edit; the single thing the UI binds to.
- *(planned)* `Operation` — a reversible move / mkdir / trash; the unit of apply
  and undo.

Execution always goes through the engine, so any future second front-end applies
changes through identical code.

---

## 9. Testing

- `swift test` runs the engine suite headlessly (no Xcode, no display) — the
  parity contract for every rule.
- New parsing/planning code lands with mirrored cases from the Python
  `tests/test_renamer.py` oracle.
- SwiftUI views stay thin; logic lives in the testable engine. UI tests are
  post-MVP.

---

## 10. Open Decisions

1. **App project layout** — Xcode project at repo root referencing
   `./RenamerCore` via a local package path (recommended) vs an Xcode workspace.
2. **Online verification provider** — TMDb vs TVDB; API-key storage (Keychain).
   Deferred to M7.
3. **Undo depth** — last run only (recommended) vs a multi-step history.
4. **Settings surface** — `@AppStorage` for the MVP; revisit if it grows.
