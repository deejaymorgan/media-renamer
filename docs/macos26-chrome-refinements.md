# Media Renamer UI refinements — macOS 26 chrome

**Status: resolved.** The three agenda items below are done and were verified by
building and visually checking the running app on macOS 26 (first folder load,
no resize). This file now records the fixes and the reasoning behind them.

Environment: **macOS 26.5 / Xcode 26.5**. The chrome issues were macOS 26
("Liquid Glass") behaviours and don't reproduce on macOS 14/15. The app targets
macOS 14+ but is run on 26.

Work landed on branch **`ui-polish`**.

---

## 1. Summary counts moved to the bottom bar — done

The per-category counts (`N TV · N Movies · N Unchanged · N Skipped ·
N Conflicts · N Junk`) are gone from the `.primaryAction` toolbar slot (and with
them the unsolved macOS-26 capsule-spacing problem). They now render as
**colour-coded chips** in [`ContentView.swift`](../MediaRenamer/MediaRenamer/ContentView.swift)'s
`BottomBar`, trailing-aligned after Apply and the
"N files will move · N junk to Trash" note (a `Spacer(minLength: 16)` keeps them
off the note). Chips:

- only non-zero categories show, so the row stays tight on small folders;
- a faint tinted `Capsule` + coloured count per category, neutral grey for
  Unchanged/Skipped — colours come from the shared `Palette` (below).

## 2. Inspector title clears the acronym bar on first layout — done (title-bar accessory)

**Root cause (confirmed):** the `NavigationSplitView` joins the macOS 26 unified
title bar and mis-propagates the toolbar height into the detail column's top
safe area (the documented `rdar://122947424`). With the acronym bar as a SwiftUI
*sibling* above the split view, the detail's `ScrollView` content underlapped the
bar's `.regularMaterial` on the **first** layout pass — the headline rendered
under the material (blurred, hairline above). A window resize forced a geometry
re-resolution that fixed it and stuck; nothing else recomputed it. The sidebar
`List` was immune because it self-insets.

**What did NOT work (verified empirically on macOS 26):**
- `contentMargins(.top, 34)` — the original band-aid: constant gap, blur still on
  first load. Removed.
- `.safeAreaInset(edge:.top)` for the bar on the split view — *worse*: the same
  bug double-counts the inset and **permanently clips** the first row (resize does
  not fix it).
- Hoisting the headline into a fixed, non-scrolling header — the detail content
  still underlapped, because the whole column (scroll or not) sat under the
  mis-propagated inset.

**The fix:** host the acronym bar as a real **`NSTitlebarAccessoryViewController`**
(`layoutAttribute = .bottom`) — see
[`AcronymTitlebar.swift`](../MediaRenamer/MediaRenamer/AcronymTitlebar.swift). It's
genuine window chrome, so AppKit reserves its space and computes the content safe
area correctly; the detail title clears the bar on the very first layout with
spacing that matches the rest of the UI — no blur, no clip, no resize, no magic
constant. The accessory is added/removed as acronym words come and go, and its
SwiftUI content (`AcronymBar`, unchanged) stays live against the shared `AppModel`
(toggling a chip still re-plans the whole folder). `ContentView` installs it via
`.background(AcronymTitlebar(model:))`; the old VStack-sibling bar and the
`clearAcronymBarBlur` extension are gone.

## 3. Original vs renamed names are colour-coded — done

New [`Palette.swift`](../MediaRenamer/MediaRenamer/Palette.swift) holds one legend
used everywhere:

- **Names** — the *new* name is `Palette.renamed` (green, reads like a diff
  addition); the *original* stays muted via `.secondary`. Applied in `PairRow`
  (Resulting files), the `AllCard` collapsed preview, and the conflict resolver's
  `→ result` line. The inspector "from …" line and sidebar subtitles are originals
  and stay `.secondary`.
- **Categories** — TV blue, Movie purple, Conflict red, Junk orange, Verify
  orange. The summary chips and the flag badges (`dup`/`junk`/`verify`) both pull
  from here, so a category reads the same colour wherever it appears (the junk
  badge/trash icon moved red → orange to match the Junk chip).

### Also done (the optional suggestions)
- Sidebar/card titles: tail truncation + a full-name `.help()` tooltip (TV shows
  and All-mode cards). Movie rows keep middle truncation so the `(Year)` suffix
  stays visible, plus the tooltip. Fixes the awkward
  "The Lord of the Rin…rn of the King" mid-title clipping.

---

## Build / run / reproduce
- Build: `xcodebuild -project MediaRenamer/MediaRenamer.xcodeproj -scheme MediaRenamer -destination 'platform=macOS' build`
- Reproduce the old §2 bug (pre-fix): open a folder whose names contain ALL-CAPS
  acronyms so the bar appears — e.g. the local `Test Files` folder (`FBI` /
  `WALL`). The blur showed on first load and vanished on resize; with the
  title-bar accessory it never appears.
