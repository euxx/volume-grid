# Rules

- Keep context window clear by using sub-agents for planning, research, and lengthy coding tasks.
- Use TO-DOs and sub-agents to manage tasks efficiently and keep context window free.
- Research #changes or #codebase extensively until fully understanding the issue.
- Think deeply to determine the root cause and how to address it.
- Ensure consideration of existing unit tests and behaviors to understand side effects of a potential fix.
- Add temporary logs when debugging complex issues, then remove them after resolution.
- Remove unnecessary comments.
- Check VSCode lint problems.

## Always Show HUD Scenarios

- When pressing volume keys or mute key
- When switching output devices
- When volume changes

## Development

Run commands after code changes to ensure consistent formatting:
```sh
swift-format lint --recursive .
swift-format format --recursive --in-place .
```

Run unit tests:
```sh
xcodebuild test -scheme "Volume Grid"
```

Try building the project to verify correctness:
```sh
rm -rf .build

xcodebuild -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release -derivedDataPath .build/volumegrid-build 2>&1 | grep -i warning
```

## Build DMG Locally

```sh
VERSION="v1.0.0"
TIMESTAMP="202511301130"
TIMESTAMP_DATE="11/30/2025 11:30:00"

xcodebuild -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

DMG_DIR="dmg-dir-temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -r "build/Build/Products/Release/Volume Grid.app" "$DMG_DIR/"
find "$DMG_DIR/Volume Grid.app" -exec touch -t $TIMESTAMP {} + 2>/dev/null

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
```

## Release

1. Update CHANGELOG.md:
   - Add version entry: `## [X.Y.Z] - YYYY-MM-DD` with changes

2. Update version in `VolumeGrid/Info.plist`:
   - Update `CFBundleShortVersionString` to `X.Y.Z`
   - Update `CFBundleVersion` to build number (e.g., `1`, `2`, `3`)

3. Update version in `VolumeGrid.xcodeproj/project.pbxproj`:
   - Update `MARKETING_VERSION = X.Y.Z` (must match CFBundleShortVersionString)
   - Update `CURRENT_PROJECT_VERSION = N` (must match CFBundleVersion)

4. Commit if changes were made:
```sh
git add CHANGELOG.md VolumeGrid/Info.plist VolumeGrid.xcodeproj/project.pbxproj
git commit -m "chore: update version to vX.Y.Z"
git push origin main
```

5. Create a GitHub release:
```sh
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

GitHub Actions workflow will automatically build DMG, update Cask, and publish release.
