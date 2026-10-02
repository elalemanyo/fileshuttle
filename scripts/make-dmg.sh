#!/usr/bin/env bash
# Builds FileShuttle-<version>.dmg without an Apple Developer account.
# The app is ad-hoc signed, so on first launch users must allow it once:
# System Settings → Privacy & Security → "Open Anyway".
#
# Usage: scripts/make-dmg.sh
#   VERSION=2.1.0 BUILD_NUMBER=42 scripts/make-dmg.sh   # override the version from project.yml
set -euo pipefail
# Use full Xcode when the active developer dir is only the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

VERSION_OVERRIDES=()
[[ -n "${VERSION:-}" ]] && VERSION_OVERRIDES+=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

cd "$(dirname "$0")/.."
OUT=build/dmg
rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate -q

xcodebuild build -quiet \
  -project FileShuttle.xcodeproj -scheme FileShuttle -configuration Release \
  -derivedDataPath build/dmg-derived \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ${VERSION_OVERRIDES[@]+"${VERSION_OVERRIDES[@]}"}

APP=build/dmg-derived/Build/Products/Release/FileShuttle.app
# Re-sign ad hoc with hardened runtime, inside out, as Sparkle documents.
# No --deep: it would put the app's entitlements on Sparkle's helpers.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign -f -s - -o runtime --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/Autoupdate"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/Updater.app"
codesign -f -s - -o runtime "$SPARKLE"
codesign -f -s - -o runtime --entitlements App/FileShuttle.entitlements "$APP"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE="$OUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open.txt" <<'TXT'
FileShuttle isn't signed with a paid Apple Developer ID, so macOS blocks it the first time.

1. Drag FileShuttle to Applications.
2. Open it. macOS will say it can't verify the app. Click "Done".
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway".
4. Open FileShuttle again and confirm. You only need to do this once.

Alternatively, run this in Terminal:
  xattr -dr com.apple.quarantine /Applications/FileShuttle.app
TXT

DMG="$OUT/FileShuttle-$VERSION.dmg"
hdiutil create -quiet -volname "FileShuttle $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
# Let CI pick up the path.
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "dmg=$DMG" >> "$GITHUB_OUTPUT"
exit 0
