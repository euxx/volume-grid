# VolumeGrid

macOS Tohoe 26 changed the system volume HUD: it now appears only as a single bar in the top-right corner of the active display, removing the classic 16-tile feedback.

VolumeGrid restores that classic HUD and adds the current output device indicator introduced in macOS Tohoe 26. It is designed for users who often adjust volume or work with multiple displays.

## Features

- 🎵 Restores the classic volume HUD style
- 🖥️ Supports multiple displays
- 📊 Shows 16 tiles with quarter-tile increments for precise feedback
- 🔄 Automatically listens for device changes and shows the HUD when, for example, a Bluetooth headset connects
- 📱 Provides menu bar controls
- 🔄 Supports launch at login

## Usage

1. Download the latest release from the [Releases](https://github.com/euxx/VolumeGrid/releases) page.
2. Launch the app; it will continue to run in the background.
3. A volume icon appears in the menu bar.
4. Adjusting the system volume shows the classic HUD overlay.
5. Click the menu bar icon to view the current volume and output device.
6. Enable launch at login from the menu if desired.

## Development

### Run Options

- Double-click the `.app`, or run `open build/Build/Products/Release/VolumeGrid.app`
- In Xcode choose `Product > Run` (shortcut `⌘R`) to debug directly
- Command-line build: `xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build`

### Code Quality Tools

This project uses the following tools to maintain code quality and consistency:

- **swift-format**: Apple's official Swift code formatter focused on consistent style.
  - Install: `brew install swift-format`
  - Run (lint): `swift-format lint --recursive .`
  - Run (format): `swift-format format --recursive --in-place .`
  - Config: `.swift-format` (JSON format that sets indentation, line length, and more)
  - Integration: Added to the Xcode Build Phase for automatic formatting.

These tools ensure code adheres to project standards and run automatically during development.

## TODOs

- [x] Dark and light mode support / adapt HUD colors to the background
- [x] Display a mute icon
- [ ] Choose an open-source license
- [x] Automate releases with GitHub Actions
- [ ] Add internationalization
- [ ] Create an app icon
- [x] Finalize launch-at-login behavior
- [x] About view with app version and contact details
- [x] Rename the project
- [x] Replace all Chinese content with English
- [x] Linters, type checkers, auto-formatters
