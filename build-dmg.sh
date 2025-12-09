#!/bin/bash

set -e

VERSION="v1.0.0"
TIMESTAMP="202511301130"
TIMESTAMP_DATE="11/30/2025 11:30:00"

IDENTITY=$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F\" '{print $2}')

echo "Using code signing identity: $IDENTITY"

xcodebuild -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES

DMG_DIR="dmg-dir-temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -r "build/Build/Products/Release/Volume Grid.app" "$DMG_DIR/"
find "$DMG_DIR/Volume Grid.app" -exec touch -t $TIMESTAMP {} + 2>/dev/null

codesign --verify --deep --strict --verbose=4 "$DMG_DIR/Volume Grid.app"
codesign -dv --verbose=4 "$DMG_DIR/Volume Grid.app"

create-dmg \
  --volname "Volume Grid" \
  --window-pos 200 200 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Volume Grid.app" 200 200 \
  --app-drop-link 400 200 \
  "VolumeGrid-${VERSION}.dmg" \
  "$DMG_DIR"

touch -t $TIMESTAMP "VolumeGrid-${VERSION}.dmg"
date -r "VolumeGrid-${VERSION}.dmg"
stat "VolumeGrid-${VERSION}.dmg"

rm -rf build "$DMG_DIR"

echo "DMG build completed: VolumeGrid-build-${VERSION}.dmg"
