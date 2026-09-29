#!/usr/bin/env bash
# Builds a Developer ID signed, notarized FileShuttle.zip ready to share.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain (Xcode > Settings > Accounts).
#   2. xcrun notarytool store-credentials fileshuttle --apple-id you@example.com --team-id TEAMID
#
# Usage: TEAM_ID=TEAMID scripts/release.sh
set -euo pipefail
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-fileshuttle}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$(dirname "$0")/.."
OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate -q

xcodebuild archive -quiet \
  -project FileShuttle.xcodeproj -scheme FileShuttle -configuration Release \
  -archivePath "$OUT/FileShuttle.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -quiet \
  -archivePath "$OUT/FileShuttle.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT"

APP="$OUT/FileShuttle.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$OUT/FileShuttle-$VERSION.zip"
rm "$OUT/notarize.zip"
echo "✅ $OUT/FileShuttle-$VERSION.zip"
