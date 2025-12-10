# Rules

- Keep context window clear by using sub-agents for planning, research, and lengthy coding tasks.
- Use TO-DOs and sub-agents to manage tasks efficiently and keep context window free.
- Research #changes or #codebase extensively until fully understanding the issue.
- Think deeply to determine the root cause and how to address it.
- Ensure consideration of existing unit tests and behaviors to understand side effects of a potential fix.
- Add temporary logs when debugging complex issues, then remove them after resolution.
- Remove unnecessary comments.
- Check VSCode lint problems.
- 

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

See [RELEASE.md](RELEASE.md) for release instructions.
