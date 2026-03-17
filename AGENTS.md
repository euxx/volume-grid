# Project Conventions

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

## Always Show HUD Scenarios

- When pressing volume keys or mute key
- When switching output devices
- When volume changes

See [RELEASE.md](RELEASE.md) for release instructions.
