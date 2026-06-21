# M8 — Packaging for distribution (handoff agenda)

**Status:** Shippable UNSIGNED (ad-hoc) now · notarised path deferred · **Updated:** 2026-06-21 · **Branch:** `main`

Distribution **is in scope** (decided 2026-06-21): a `.app` that runs outside
Xcode. **Decision (2026-06-21): ship UNSIGNED (ad-hoc) for now** — no paid Apple
Developer account. `scripts/package-unsigned.sh` builds a shareable zip today;
recipients open it once past Gatekeeper (right-click → Open). The notarised,
double-click-clean path is fully prepped (`scripts/notarize.sh`) and waiting only
on a Developer ID account — pick it up whenever that's worth $99/yr. The
functional core is done and green; M8 is build/release plumbing, not app logic.

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
| Gap | State | Notes |
|-----|-------|-------|
| App icon | ✅ DONE (placeholder) | 7 PNGs (16–1024px) rendered into the iconset; **placeholder art** — replace before 1.0 |
| Hardened Runtime | ✅ DONE | `ENABLE_HARDENED_RUNTIME = YES` in both Debug + Release target configs |
| Entitlements | ✅ DONE | `MediaRenamer.entitlements` (intentionally empty; sandbox off, no exceptions needed) + `CODE_SIGN_ENTITLEMENTS` wired in both configs |
| LICENSE | ✅ DONE | MIT, "Daniel Morgan", 2026, at repo root |
| Unsigned packaging | ✅ DONE | `scripts/package-unsigned.sh` builds a universal ad-hoc app + shareable zip; **runs today, no account** |
| Notarise script | ✅ DONE | `scripts/notarize.sh` — archive→export→notarytool→staple, with a release checklist (for the paid path) |
| Signing identity | ⏸ DEFERRED | Chose unsigned for now. Only needed for the notarised path: a `DEVELOPMENT_TEAM` + Developer ID cert |
| Sandbox | ✅ left OFF | Correct for Developer-ID distribution *outside* the App Store |
| Bundle ID | ✅ `com.djmorgan.MediaRenamer` | — |

## Plan
**Solo-doable (no credentials needed) — ✅ DONE this session:**
1. ✅ `LICENSE` at repo root — MIT, Daniel Morgan.
2. ✅ Hardened Runtime on (both configs) + `MediaRenamer/MediaRenamer/MediaRenamer.entitlements`
   (empty dict — a non-sandboxed Developer-ID app doing FileManager moves/trash +
   NSOpenPanel needs no exceptions). `CODE_SIGN_ENTITLEMENTS` wired in both configs.
   Also flipped the leftover `ENABLE_USER_SELECTED_FILES = readonly` → `NO` so no
   stray sandbox entitlement leaks into the (non-sandboxed) build.
3. ✅ `scripts/notarize.sh` (archive → export Developer ID → `notarytool submit
   --wait` → `stapler staple` → verify) with `TEAM_ID` / `SIGNING_IDENTITY` /
   `NOTARY_PROFILE` as top variables, a placeholder guard, and a RELEASE checklist
   in the header. **Not run** (needs credentials); `bash -n` syntax-clean.
4. ✅ Placeholder app icon — `scripts/make_icon.swift` (AppKit/CoreGraphics, no
   deps) renders a film glyph on an indigo→blue squircle into the iconset.
   **Placeholder — replace with real art before 1.0.**
5. ✅ Shared the `MediaRenamer` scheme
   (`…xcodeproj/xcshareddata/xcschemes/MediaRenamer.xcscheme`, Archive→Release) so
   `notarize.sh`'s `xcodebuild archive -scheme MediaRenamer` is reproducible on a
   clean clone / another machine / CI — previously the scheme lived only in
   git-ignored `xcuserdata/`.
6. ✅ `scripts/package-unsigned.sh` — the chosen path. Builds a **universal**
   (`x86_64 + arm64`) ad-hoc-signed Release `.app` and zips it to
   `build/MediaRenamer-unsigned.zip`, then prints recipient instructions. **Run &
   verified**: build succeeds, `Signature=adhoc`, `spctl` rejects (expected for
   unsigned — recipients open once via right-click → Open).

Verified after the changes: `swift test --package-path RenamerCore` = **92 tests /
11 suites green**; Debug **and** Release `xcodebuild … build` = **BUILD SUCCEEDED**;
`xcodebuild -list` finds the now-shared scheme. Embedded entitlements on the local
build are just `get-task-allow` (auto-added for local signing; **stripped by the
`developer-id` export**), so the notarised app carries an empty entitlement set.

A 5-dimension adversarial review (pbxproj, entitlements, notarize.sh, LICENSE,
icon) found **zero blockers**. The shared-scheme gap above was its one verified
warning (now fixed); `codesign --verify` dropped the Apple-discouraged `--deep`.

### Optional future cleanup (inert, not blocking)
- `REGISTER_APP_GROUPS = YES` is a leftover Xcode-template setting in both target
  configs. It injects nothing (no app-groups array; confirmed by the clean build)
  and is harmless, so it was left as-is. Can be removed for a more minimal,
  intention-revealing non-sandboxed config.

## Ship an unsigned build now (chosen path)
```sh
./scripts/package-unsigned.sh        # -> build/MediaRenamer-unsigned.zip
```
Send the zip. Recipients open it once past Gatekeeper (right-click → Open; or
clear quarantine with `xattr -dr com.apple.quarantine MediaRenamer.app`). No
Apple account, no cost. Caveat: every recipient sees the first-launch warning.

## Later: switch to notarised (only if/when worth $99/yr)
A paid **Apple Developer Program** membership is required — a free Apple ID
cannot issue a Developer ID cert or notarise. When ready:
- Set `DEVELOPMENT_TEAM` (Team ID) + a Developer ID Application certificate.
- Fill `TEAM_ID` / `SIGNING_IDENTITY` in `scripts/notarize.sh` (or export them).
- One-time: `xcrun notarytool store-credentials` (app-specific password).
- Run `./scripts/notarize.sh`. Result: double-click-clean, no warnings.
- Replace the placeholder icon with final art before a real 1.0 either way.

## Open decisions — resolved
- **License:** MIT ✅
- **Icon:** placeholder generated now ✅ (real art before 1.0)
- **Distribution:** unsigned (ad-hoc) for now ✅; notarised deferred

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
