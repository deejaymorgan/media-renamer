# macOS 26 chrome refinements — working notes

**Status: in progress, not finished.** This branch makes *minor* spacing
improvements to the toolbar summary and the inspector header on macOS 26
(Tahoe / "Liquid Glass"). They read a little better than before, but are **not
yet right** — both still need another pass. These notes are a handoff so the
work can be picked up in a later session.

Environment where this was observed: **macOS 26.5 / Xcode 26.5**. These are
macOS 26 "Liquid Glass" behaviours and do not reproduce on macOS 14/15. The app
targets macOS 14+ but is being run on 26.

---

## 1. Toolbar summary chips

`SummaryChips` in [`MediaRenamer/MediaRenamer/ContentView.swift`](../MediaRenamer/MediaRenamer/ContentView.swift)
(the `"N TV  N Movies  N Unchanged  …"` row, `.primaryAction` toolbar item).

macOS 26 wraps toolbar items in a rounded glass capsule.

**Changed this session (minor):**
- Inter-chip gap `12 → 16`, number↔label gap `3 → 4`.
- `.monospacedDigit()` on the counts so widths don't jitter.
- Symmetric `.padding(.horizontal, 8)` (was trailing-only, which left the
  leading count jammed against the capsule's left curve).

**Still not right:** the overall grouping/spacing inside the capsule isn't quite
there yet. Worth revisiting — e.g. the gap ratio, a subtle divider between chips,
or the capsule padding itself.

---

## 2. Inspector title blurred by the acronym bar

Detail pane in [`MediaRenamer/MediaRenamer/Inspector.swift`](../MediaRenamer/MediaRenamer/Inspector.swift)
(`InspectorView` / `SeasonInspectorView` / `AllModeView`).

**Diagnosis (confirmed):** when the acronym bar is showing, the detail's
`ScrollView` content slides up *under* the bar's translucent `.regularMaterial`,
which blurs its first row — the headline title — into a washed-out strip with a
hairline above it. Confirmed by loading an acronym-free folder: with no acronym
bar, the title is crisp. The sidebar uses a `List`, which insets itself, so it
was never affected.

**Changed this session (partial):** added a `clearAcronymBarBlur(active:)` helper
that applies `contentMargins(.top, 34, for: .scrollContent)` to the three detail
scroll views, gated to macOS 26 **and** to the acronym-bar-present case.
- The title is no longer blurred — **but** clearing the blur pushes the content
  down ~34pt, leaving a top gap whenever the bar is shown. Legible, not clean.
- `34` is a magic number tuned by eye (the blur clears around ~28pt).

**Approaches tried and rejected — don't repeat:**
- `scrollEdgeEffectStyle(.hard, for: .top)` — no effect on the blur.
- `scrollEdgeEffectHidden(true, for: .top)`, on both the inner `ScrollView` and
  the `NavigationSplitView` — no effect. The blur is the bar's material, not a
  scroll-edge effect, so these APIs don't touch it.
- Moving the acronym bar into `.safeAreaInset(edge: .top)` on the
  `NavigationSplitView` — **clipped the first row of both columns** (the detail
  title *and* the sidebar's "All items"). The edge-to-edge detail `ScrollView`
  ignores the inset.

**Possible next directions:**
- Find a gap-free way to stop the content underlapping the bar — e.g. a fixed,
  non-scrolling header holding the title *outside* the `ScrollView`, or
  restructuring so the detail scroll view genuinely insets below the bar.
- If keeping `contentMargins`, derive the inset from the bar's actual measured
  height instead of a constant (and/or drop toward the ~28pt threshold).

---

## Verifying

- Build: `xcodebuild -project MediaRenamer/MediaRenamer.xcodeproj -scheme MediaRenamer -destination 'platform=macOS' build`
- The inspector blur **only** appears when the acronym bar is visible — load a
  folder whose names contain an ALL-CAPS word (e.g. `The.Office.US.S03E07.mkv`)
  to make the bar (and the issue) show.
