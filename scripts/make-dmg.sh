#!/usr/bin/env bash
#
# make-dmg.sh — wrap the built MediaRenamer.app in a drag-to-install .dmg.
#
# Expects the universal, ad-hoc app to already be built by
# scripts/package-unsigned.sh (it reads the same derived-data location). The
# .dmg is NOT notarised — recipients clear Gatekeeper on first launch exactly as
# for the .zip (see README "Download & run" / the notes printed below).
#
#   ./scripts/package-unsigned.sh   # build the app first
#   ./scripts/make-dmg.sh           # -> build/MediaRenamer-<version>.dmg
#
set -euo pipefail

CONFIGURATION="Release"
VOL_NAME="Media Renamer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_PATH="$REPO_ROOT/build/dd/Build/Products/$CONFIGURATION/MediaRenamer.app"
[ -d "$APP_PATH" ] || {
  echo "error: $APP_PATH not found — run scripts/package-unsigned.sh first" >&2
  exit 1
}

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# Name the .dmg after the app's own version so it can never drift from the build.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$REPO_ROOT/build/MediaRenamer-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

log "Staging app + /Applications symlink for drag-install"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

log "Creating $DMG_PATH (compressed, read-only)"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

log "Verifying image"
hdiutil verify "$DMG_PATH"

log "App signature inside the image (expect 'Signature=adhoc')"
codesign -dvv "$APP_PATH" 2>&1 | grep -E 'Signature' || true

cat <<NOTES

──────────────────────────────────────────────────────────────────────────────
Done. Share: $DMG_PATH

Like the .zip, this is ad-hoc signed and NOT notarised, so the first launch on
someone else's Mac is blocked by Gatekeeper. After dragging the app to
Applications, recipients open it once via: System Settings -> Privacy & Security
-> "Open Anyway" (macOS 15+), or right-click -> Open (macOS 14). See the README
"Download & run" section for the exact, current steps.
──────────────────────────────────────────────────────────────────────────────
NOTES
