# Release Guide

## Steps to Release a New Version

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

6. Build the DMG installer:

Edit [build-dmg.sh](build-dmg.sh) to set `VERSION` and `TIMESTAMP`, then run:

```sh
chmod +x build-dmg.sh
./build-dmg.sh
```

7. Update the release notes on GitHub to match `CHANGELOG.md`:

   Write the notes in Markdown format to a temp file, then pass it via `--notes-file`:

   ```sh
   gh release edit vX.Y.Z --notes-file /path/to/notes.md
   ```

   Notes format:

   ```markdown
   ## What's Changed

   ### Added/Changed/Fixed

   - Change 1
   - Change 2

   **Full Changelog**: https://github.com/euxx/volume-grid/compare/vPREV...vX.Y.Z
   ```
