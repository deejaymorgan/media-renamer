# Claude knowledge (distilled from auto-memory, 2026-07-10)

Working knowledge distilled from Claude's per-project auto-memory on 2026-07-10, before a Claude factory reset wiped it. README, SPEC.md, and CLAUDE.md stay canonical; this file holds the cross-session operational facts that lived nowhere else.

## Publishing guardrails

- This repo is public. `main`'s history is email-clean: commits carry the GitHub noreply identity, and the author's personal email must never enter history. Keep the commit identity exactly as configured.
- Never `git push --tags` and never `git push --mirror`. Publish with `git push origin main`, and cut releases with `gh release create` (it pushes only the named tag). The local backup tag that once held pre-rewrite history (`_backup_pre_email`) has since been deleted (verified 2026-07-10: local and remote both carry only `v1.0.0` and `v1.1.0`), so the original landmine is gone, but the rule stands as cheap insurance.
- Accepted in the 2026-06-22 pre-open-source review, so do not re-flag: the author's real name in LICENSE/README/app header, the bundle id, and the `/Users/daniel/...` paths visible in the quick-start screenshots.
- `notes/` (dev handoffs) and `build/` (artifacts) are gitignored on purpose; never commit them. Release binaries go up only as GitHub Release assets.

## Dev-loop gotchas

- Relaunch after rebuild: `open` on a running MediaRenamer only refocuses the stale binary, so edits look like they "did nothing". Run `killall MediaRenamer` before `open`. The app resets state on relaunch, so the folder has to be re-picked each time.
- Worktree check: a session often roots at the `main` checkout while the owner builds and runs the app from a different worktree. If a UI change does not show up, run `git worktree list` and compare against the folder path in the app's title bar before editing further.
- "Window won't drag between displays" is macOS full-screen-Spaces behavior, not an app bug: a display showing a full-screen app rejects normal windows. Ask whether the other display is in full-screen mode before touching code (investigated 2026-06-21; the min-window-size hypothesis was tested and refuted).
- App screenshots while running under the Claude desktop app: `screencapture` from Bash is blocked (no Screen Recording permission; do not change that setting). The working path is to temporarily point the `com.apple.screencapture` defaults at a directory (the owner's default target is `clipboard`), drive the OS window capture (Cmd+Shift+4 then Space) via computer-use, then restore the owner's defaults. The owner often prefers to shoot the screenshots himself once the app is staged ("you set up the app, I'll shoot").
- Release flow (the v1.0.0/v1.1.0 pattern): `scripts/package-unsigned.sh`, then `scripts/make-dmg.sh`, then `gh release create vX.Y.Z --target main --latest`, bumping `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` first. The installed `gh` rejects `gh release view --json isLatest`; confirm the Latest flag with `gh release list`. Gatekeeper first-launch bypass steps are documented in README and were verified against Apple's release notes; the ad-hoc signature is what makes `xattr -dr com.apple.quarantine` sufficient (a truly unsigned arm64 binary would be killed regardless).

## History

- The predecessor `tv-show-renamer` (Python CLI) was permanently deleted on 2026-06-27 by explicit owner choice: local repo, its Claude skill, its config, and the GitHub remote are all gone, with no backup. It survives only as the behavioral spec and parity-test oracle mirrored by RenamerCore's tests. Do not look for it or try to restore it. Consequence: media-renamer is GUI-only and there is no scriptable or headless renaming tool anymore.
