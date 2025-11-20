# Rules

- Research #changes or #codebase extensively until fully understanding the issue.
- Think hard to determine root cause and solution thoroughly.
- Consider existing behaviors to understand side effects of fixes.
- Present a few options and open questions when appropriate.
- Don't say sentences that begin with perfect or similar.
- Remove unnecessary comments.
- Check VSCode lint problems.

## Development

Run commands after code changes to ensure consistent formatting:
```sh
swift-format lint --recursive .
swift-format format --recursive --in-place .
```

Try building and running the project to verify correctness:
```sh
xcodebuild -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release -derivedDataPath ~/Downloads/volumegrid-build 2>&1 | grep -i warning

xcodebuild clean -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

xcodebuild -project VolumeGrid.xcodeproj -scheme "Volume Grid" -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

killall "Volume Grid"

open ~/Downloads/volumegrid-build/Build/Products/Release/Volume\ Grid.app
```

## Release

### Update Version

1. Update CHANGELOG.md:
   - Add version entry: `## [X.Y.Z] - YYYY-MM-DD` with changes

2. Update version in `VolumeGrid/Info.plist`:
   - Update `CFBundleShortVersionString` to `X.Y.Z`
   - Update `CFBundleVersion` to build number (e.g., `1`, `2`, `3`)

3. Update version in `VolumeGrid.xcodeproj/project.pbxproj`:
   - Update `MARKETING_VERSION = X.Y.Z` (must match CFBundleShortVersionString)
   - Update `CURRENT_PROJECT_VERSION = N` (must match CFBundleVersion)

4. Commit and release:
```sh
git add CHANGELOG.md VolumeGrid/Info.plist VolumeGrid.xcodeproj/project.pbxproj
git commit -m "chore: update version to vX.Y.Z"
git push origin main
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

GitHub Actions workflow will automatically build DMG, update Cask, and publish release.
