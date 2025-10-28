# Rules

Run commands after code changes to ensure consistent formatting:
- lint: `swift-format lint --recursive .`
- format: `swift-format format --recursive --in-place .`

Try building and running the project to verify correctness:
- Clean: `xcodebuild clean -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build`

- Fix warning: `xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build 2>&1 | grep -i warning`

- Build: `xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build`

- Quit: `killall VolumeGrid` if it is already running.
- Run: `open ~/Downloads/volumegrid-build/Build/Products/Release/VolumeGrid.app`
