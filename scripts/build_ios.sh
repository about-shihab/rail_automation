#!/usr/bin/env bash
set -euo pipefail

# Ensure script is run from project root
cd "$(dirname "$0")/.."

echo "=== Building iOS App for Rail Pro ==="

# 1. Fetch dependencies
flutter pub get

# 2. CocoaPods setup
cd ios
pod install --repo-update
cd ..

# 3. Build iOS Archive (Unsigned)
flutter build ipa --no-codesign

# 4. Package .ipa from Runner.xcarchive
ARCHIVE_APP="build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
IPA_DIR="build/ios/ipa"

if [ -d "$ARCHIVE_APP" ]; then
  echo "=== Packaging .ipa artifact ==="
  rm -rf "$IPA_DIR"
  mkdir -p "$IPA_DIR/Payload"
  cp -R "$ARCHIVE_APP" "$IPA_DIR/Payload/"
  cd "$IPA_DIR"
  zip -r -y "RailPro.ipa" "Payload"
  cd - > /dev/null
  echo "=== Successfully created $IPA_DIR/RailPro.ipa ==="
else
  echo "Error: Archive app not found at $ARCHIVE_APP"
  exit 1
fi
