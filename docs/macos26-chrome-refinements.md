# Media Renamer UI refinements — working notes

**Status: in progress, not finished.** Only *minor* improvements have landed so
far; the items in "Agenda" below are still open and are the work for the next
session. This file is a self-contained handoff — read it before continuing.

Environment: **macOS 26.5 / Xcode 26.5**. The chrome issues are macOS 26
("Liquid Glass") behaviours and don't reproduce on macOS 14/15. The app targets
macOS 14+ but is run on 26.

Resume from branch **`ui-polish`** (it holds all commits + this doc).

---

## Agenda (next session)

### 1. Move the summary counts out of the toolbar, into the bottom bar
`SummaryChips` in [`ContentView.swift`](../MediaRenamer/MediaRenamer/ContentView.swift) —
the `"N TV  N Movies  N Unchanged  N Skipped  N Conflicts  N Junk"` row in the
`.primaryAction` toolbar slot. macOS 26 wraps it in a rounded glass capsule, and
the spacing there still isn't right despite tweaks (below).

**Decision:** stop fighting the capsule — **relocate the summary to the bottom
bar, next to "Apply renames."** It already reads "N files will move · N junk to
Trash"; the per-category counts are a natural "what's about to happen" summary
and belong there. This also removes the capsule-spacing problem entirely.
- Suggested: render the counts as colour-coded chips matching the category
  colours used elsewhere (TV blue, Movies purple, Conflicts red, …).
- `BottomBar` is in `ContentView.swift`; `SummaryChips` + `PlanGroups` already
  compute the counts and can be reused/moved.
- Minor work already done in the toolbar (likely throwaway once relocated):
  inter-chip gap 12→16, number↔label 3→4, `.monospacedDigit()`, symmetric
  `.padding(.horizontal, 8)`.

### 2. Fix the top spacing above the inspector title *properly* (current fix is a band-aid)
Detail pane in [`Inspector.swift`](../MediaRenamer/MediaRenamer/Inspector.swift)
(`InspectorView` / `SeasonInspectorView` / `AllModeView`).

**Symptom:** with the acronym bar showing, the detail `ScrollView`'s first row
(the headline title) sits under the bar's translucent `.regularMaterial` and gets
blurred, with a hairline above it.

**Key clue (new):** the blur is only present on **initial folder load** —
**resizing the window makes it disappear and it stays gone.** (You must load a
folder *with an acronym* first to see it.) That points to an **initial-layout /
safe-area-settling bug**: on first layout the detail content underlaps the bar; a
resize forces a correct relayout.

**The current code is a band-aid — reconsider/revert it.** `clearAcronymBarBlur(active:)`
applies a constant `contentMargins(.top, 34, …)`. It does **not** actually solve
the problem: the blur still shows on first load, and the constant inset leaves an
**inconsistent gap** above the title. The goal is the opposite — the space above
the title should be **consistent with the rest of the UI**, with no blur.

**Already tried (don't repeat):**
- `scrollEdgeEffectStyle(.hard,…)` / `scrollEdgeEffectHidden(…)` on the inner
  `ScrollView` and on the `NavigationSplitView` — no effect (the blur is the
  bar's material, not a scroll-edge effect).
- `contentMargins(.top, 34)` band-aid — insufficient (above).
- Acronym bar via `.safeAreaInset(edge: .top)` on the `NavigationSplitView` —
  clipped the first row of **both** columns. **But** given the resize clue, that
  clipping may itself have been the same pre-relayout artifact — worth
  **re-testing safeAreaInset and checking whether a resize corrects it too.**

**Next directions:**
- Treat it as a layout-timing bug: find why a resize fixes it, then make the
  *first* layout correct (reserve the bar's space so the detail never underlaps,
  or force a relayout when the plan loads / the acronym bar appears).
- Or hoist the title into a fixed, non-scrolling header *outside* the
  `ScrollView`, so it never sits under the bar and normal spacing applies.
- Either way: **remove the `contentMargins` band-aid** and land on top padding
  that matches the rest of the UI.

### 3. Colour-code original vs renamed names
Make it obvious at a glance which text is the *original* filename and which is the
*new* name. Apply one consistent legend (e.g. new = green/primary, original =
muted/secondary) everywhere both appear:
- Inspector "Resulting files": the new path vs the `← original.name.mkv` line.
- The inspector `from  <original>` line.
- Sidebar row subtitles (they show original filenames).
- `AllModeView` cards.

Relevant views in `Inspector.swift`: `ResultingFiles` / `SeasonResultingFiles` /
`PairRow` / `AllCard` (and `Sidebar.swift` for the row subtitles).

### Other suggestions (optional, in scope)
- Long titles truncate awkwardly *in the middle* in the sidebar (e.g. "The Lord
  of the Rin…rn of the King"). Consider tail truncation and/or a full-name tooltip.
- After the counts move to the bottom bar, make sure the badge colours
  (dup / junk / flag) line up with the new colour legend.

---

## Build / run / reproduce
- Build: `xcodebuild -project MediaRenamer/MediaRenamer.xcodeproj -scheme MediaRenamer -destination 'platform=macOS' build`
- Reproduce: open a folder whose names contain ALL-CAPS acronyms so the acronym
  bar appears — e.g. the local `Test Files` folder (has `FBI` / `WALL` titles),
  or names like `The.Office.US.S03E07.mkv`. The §2 blur shows on first load and
  vanishes on window resize.

## What actually shipped this session (minor, not solutions)
- Summary chips: gaps 12→16 / 3→4, `monospacedDigit()`, symmetric horizontal
  padding. (Superseded once the summary moves to the bottom bar — §1.)
- `clearAcronymBarBlur(active:)` `contentMargins` band-aid — to be replaced (§2).

Treat both as starting points, not finished fixes.
