#!/usr/bin/env bash
set -euo pipefail

# Ensure script is run from project root
cd "$(dirname "$0")/.."

echo "=== Building iOS App for Rail Pro ==="

# workmanager_apple references types introduced in the iOS 26 SDK.
# A runtime availability check cannot make those types compile with older SDKs.
if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: Building an IPA requires macOS with Xcode 26 or newer."
  exit 1
fi
xcodebuild -version
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
  echo "Error: iOS SDK $SDK_VERSION is too old. Select Xcode 26+ using xcode-select or DEVELOPER_DIR."
  exit 1
fi

# 1. Fetch dependencies
flutter pub get

# 2. CocoaPods setup
cd ios
pod install
cd ..

# 3. Build iOS Archive (Unsigned)
flutter build ipa --no-codesign --release

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
