#!/usr/bin/env bash
# Renders docs/preview.png (README / release image) from the real popover with demo data.
# Usage: scripts/make-preview.sh
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$(dirname "$0")/.."
mkdir -p docs
xcodegen generate -q
xcodebuild build -quiet -project FileShuttle.xcodeproj -scheme FileShuttle -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS'

# Argument-domain overrides show a demo server instead of your own settings; nothing is saved.
build/Build/Products/Debug/FileShuttle.app/Contents/MacOS/FileShuttle \
  --preview "$PWD/docs/preview.png" \
  -protocol sftp -host files.example.com -username demo -publicURL https://files.example.com/ \
  -uploadScreenshots NO -notify NO >/dev/null 2>&1
echo "✅ docs/preview.png"
