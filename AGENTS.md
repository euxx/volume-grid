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
xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build 2>&1 | grep -i warning

xcodebuild clean -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build

killall VolumeGrid

open ~/Downloads/volumegrid-build/Build/Products/Release/VolumeGrid.app
```

## Release

```sh
git tag v0.1.0
git push origin v0.1.0
```
