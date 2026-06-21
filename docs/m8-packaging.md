# M8 — Packaging for distribution (handoff agenda)

**Status:** WIP / not started · **Updated:** 2026-06-21 · **Branch:** `main`

Distribution **is in scope** (decided 2026-06-21): the goal is a notarised,
double-clickable `.app` that runs outside Xcode, not just a personal ⌘R tool.
This note is the next-session agenda. The functional core is done and green —
M8 is build/release plumbing, not app logic.

## Where things stand
- Pre-release review + hardening landed in two commits:
  - `54c9b9f` — sanitise edited titles/years at `computeDestination`, don't
    follow symlinks in `Scanner`, surface Apply skip/error reasons, doc fixes.
  - `364b0bc` — report failed empty-folder cleanup, filter the Year field to
    digits, match the resolver preview to on-disk names.
- **92 tests across 11 suites pass** (`swift test --package-path RenamerCore`);
  the app target builds clean (`xcodebuild … -scheme MediaRenamer build`).
- Working tree clean.

## M8 gap list (grounded in the actual project, 2026-06-21)
| Gap | Current state | Needed |
|-----|---------------|--------|
| App icon | `Assets.xcassets/AppIcon.appiconset` has the size slots but **no PNG art** | A 1024px icon rendered into the iconset |
| Hardened Runtime | **OFF** (absent from `project.pbxproj`) | `ENABLE_HARDENED_RUNTIME = YES` — required for notarisation |
| Signing identity | `CODE_SIGN_STYLE = Automatic`, **no `DEVELOPMENT_TEAM` / Developer ID** | Developer ID Application cert + Team ID |
| LICENSE | none at repo root | Add one (MIT is the default unless decided otherwise) |
| Sandbox | `ENABLE_APP_SANDBOX = NO` | Fine for Developer-ID distribution *outside* the App Store; leave off |
| Bundle ID | `com.djmorgan.MediaRenamer` ✓ | — |

## Plan
**Solo-doable (no credentials needed) — safe to do first:**
1. Add `LICENSE` at repo root (confirm license choice; MIT default).
2. Enable Hardened Runtime (`ENABLE_HARDENED_RUNTIME = YES`) + add a
   `MediaRenamer.entitlements` file (sandbox stays off; add only what's needed).
3. Write `scripts/notarize.sh` (archive → export Developer ID → `notarytool
   submit --wait` → `stapler staple`) + a short release checklist.
4. Optional: generate a simple placeholder app icon so the iconset isn't empty.

**Needs the user (outward-facing / credentials):**
- Developer ID Application certificate + Team ID in the project.
- Run the sign-and-notarise step with their Apple credentials
  (`notarytool` store-credentials / app-specific password).
- Provide or approve the final icon art.

## Open decisions
- **License:** MIT (recommended default) vs other.
- **Icon:** placeholder generated now, or wait for real art.

## Deferred review items (optional polish — none carry data-loss risk)
Left out of the two commits on purpose; cost ≥ value at v1.0. Full detail is in
the review session's matrix. Summary:
- Surface-only/cosmetic: give `verify` its own colour (junk + verify both
  orange today; icons already differ — `Palette.swift`).
- `ConflictChecker` doesn't pre-flag **case-only** destination collisions on
  APFS (no data loss — `moveItem` is non-overwriting; only the resolver warning
  is missing).
- Executor target-exists message doesn't distinguish a mid-Apply TOCTOU race
  from a generic error (cosmetic).
- Symlinked **files** in the input (directory symlinks are now handled).
- No pre-flight check for paths exceeding the 255-char component limit (rare;
  flag, never silently truncate).
