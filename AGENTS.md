# Rules

## Development

Run commands after code changes to ensure consistent formatting:
```sh
brew install swift-format # if not already installed
swift-format lint --recursive . # to check for style issues
swift-format format --recursive --in-place . # to auto-format code
```

Try building and running the project to verify correctness:
```sh
# Fix warning
xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build 2>&1 | grep -i warning

# Clean
xcodebuild clean -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

# Build
xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

# Quit
killall VolumeGrid # if it is already running.

# Run
open ~/Downloads/volumegrid-build/Build/Products/Release/VolumeGrid.app
```

## Release

```sh
git tag v0.1.0
git push origin v0.1.0
```
