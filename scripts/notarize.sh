#!/usr/bin/env bash
#
# notarize.sh — archive, export, notarise, and staple MediaRenamer for
# Developer-ID distribution OUTSIDE the Mac App Store.
#
#   archive (Release) -> export (Developer ID) -> notarytool submit --wait
#   -> stapler staple -> verify with spctl
#
# ─────────────────────────────────────────────────────────────────────────────
# RELEASE CHECKLIST
#   [ ] Fill in TEAM_ID and (if needed) SIGNING_IDENTITY below, or export them.
#   [ ] Have a "Developer ID Application" cert in your login keychain
#         security find-identity -v -p codesigning
#   [ ] Store notarytool credentials once as a keychain profile:
#         xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#           --apple-id "you@example.com" --team-id "<TEAM_ID>" \
#           --password "<app-specific-password>"
#   [ ] Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in the project.
#   [ ] Replace the PLACEHOLDER app icon with final art (scripts/make_icon.swift).
#   [ ] swift test --package-path RenamerCore        # green
#   [ ] ./scripts/notarize.sh
#   [ ] Confirm the final line reads: accepted / source=Notarized Developer ID
#   [ ] Ship build/MediaRenamer-notarized.zip (or wrap the .app in a .dmg).
# ─────────────────────────────────────────────────────────────────────────────
#
set -euo pipefail

# ─── Configure ───────────────────────────────────────────────────────────────
TEAM_ID="${TEAM_ID:-XXXXXXXXXX}"                                # Apple Developer Team ID (10 chars)
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}" # codesign identity (name or hash)
NOTARY_PROFILE="${NOTARY_PROFILE:-MediaRenamer}"                # notarytool keychain profile name
# ─────────────────────────────────────────────────────────────────────────────

SCHEME="MediaRenamer"
CONFIGURATION="Release"
PROJECT="MediaRenamer/MediaRenamer.xcodeproj"
APP_NAME="MediaRenamer.app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/MediaRenamer.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME"
UPLOAD_ZIP="$BUILD_DIR/MediaRenamer-upload.zip"
NOTARIZED_ZIP="$BUILD_DIR/MediaRenamer-notarized.zip"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# ─── Preflight ───────────────────────────────────────────────────────────────
if [[ "$TEAM_ID" == "XXXXXXXXXX" || -z "$TEAM_ID" ]]; then
  echo "error: set TEAM_ID at the top of this script (or run: TEAM_ID=ABCDE12345 $0)" >&2
  exit 1
fi

log "Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── 1. Archive (Release) ────────────────────────────────────────────────────
log "Archiving $SCHEME ($CONFIGURATION)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID"

# ─── 2. Export with a Developer ID profile ───────────────────────────────────
log "Writing ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${SIGNING_IDENTITY}</string>
</dict>
</plist>
PLIST

log "Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

# ─── 3. Notarise (zip the .app; notarytool needs a zip/pkg/dmg) ──────────────
log "Zipping for notarisation"
ditto -c -k --keepParent "$APP_PATH" "$UPLOAD_ZIP"

log "Submitting to notarytool (waits for the result)"
xcrun notarytool submit "$UPLOAD_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ─── 4. Staple the ticket onto the .app ──────────────────────────────────────
log "Stapling notarisation ticket"
xcrun stapler staple "$APP_PATH"

# ─── 5. Verify ───────────────────────────────────────────────────────────────
log "Verifying signature, ticket, and Gatekeeper assessment"
codesign --verify --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute -vvv "$APP_PATH"

# ─── 6. Package the stapled app for distribution ─────────────────────────────
log "Packaging stapled app -> $NOTARIZED_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZED_ZIP"

log "Done. Distribute: $NOTARIZED_ZIP"
