#!/usr/bin/env bash
#
# package-unsigned.sh — build a shareable, AD-HOC–signed MediaRenamer.app and
# zip it for distribution WITHOUT an Apple Developer account.
#
# This is the no-credentials path (see notarize.sh for the paid, notarised path).
# The result is NOT notarised, so on the recipient's Mac Gatekeeper will block it
# on first launch — they clear it once (easiest on any macOS:
# `xattr -dr com.apple.quarantine`, else System Settings -> Privacy & Security).
# See the printed notes below for the exact, per-macOS-version steps.
#
# Note: "unsigned" here means ad-hoc signed (CODE_SIGN_IDENTITY="-"). A truly
# unsigned binary will not launch on Apple Silicon; ad-hoc is the minimum.
#
#   ./scripts/package-unsigned.sh
#
set -euo pipefail

SCHEME="MediaRenamer"
PROJECT="MediaRenamer/MediaRenamer.xcodeproj"
CONFIGURATION="Release"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
DD_DIR="$BUILD_DIR/dd"
APP_PATH="$DD_DIR/Build/Products/$CONFIGURATION/MediaRenamer.app"
ZIP_PATH="$BUILD_DIR/MediaRenamer-unsigned.zip"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

log "Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build a universal Release app, forced to ad-hoc signing (no team needed).
log "Building $SCHEME ($CONFIGURATION, ad-hoc, universal)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  clean build

[ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }

log "Signature (expect 'Signature=adhoc')"
codesign -dvv "$APP_PATH" 2>&1 | grep -E 'Signature|Identifier|Authority' || true

log "Architectures"
lipo -archs "$APP_PATH/Contents/MacOS/MediaRenamer" 2>/dev/null || true

log "Zipping -> $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

cat <<NOTES

──────────────────────────────────────────────────────────────────────────────
Done. Share: $ZIP_PATH

This build is ad-hoc signed and NOT notarised, so the first launch on someone
else's Mac is blocked by Gatekeeper ("Apple could not verify…"). Recipients clear
it ONCE (assuming the app is in /Applications):

  • Easiest, ANY macOS — one Terminal line, then double-click normally:
      xattr -dr com.apple.quarantine /Applications/MediaRenamer.app
  • macOS 15 Sequoia / macOS 26 Tahoe, no Terminal: double-click once (blocked ->
    click Done), then System Settings -> Privacy & Security -> scroll to Security
    -> "Open Anyway" -> authenticate. (Apple removed Control-click -> Open here.)
  • macOS 14 Sonoma, no Terminal: Control-click MediaRenamer.app -> Open -> Open
    (Sonoma only; don't double-click first — that path has no Open button).

After the first unlock it opens normally on double-click. For a no-warning
experience you need the paid path: a Developer ID cert + notarisation
(scripts/notarize.sh).
──────────────────────────────────────────────────────────────────────────────
NOTES
