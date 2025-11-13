# VolumeGrid

Bringing back the classic volume HUD for macOS Tohoe 26 with more.

## Features

- 🎵 Classic 16-tile volume HUD with quarter-tile precision
- 🎧 Displays the sound output device and numeric volume on volume HUD
- 🖥️ Displays volume HUD on all screens
- 🔄 Displays volume HUD when switching sound output devices
- 🔊 Menu bar icon with subtle progress bar that changes with volume
- 🛠️ Native, minimal, lightweight implementation

## Installation

Recommended for macOS Tohoe 26 and later.

### Via Homebrew Cask

Recommended for automatic updates.

```bash
brew tap euxx/volumegrid
brew install --cask volumegrid
```

### Manual Download

Download the latest release from [Releases](https://github.com/euxx/VolumeGrid/releases).

## Background

macOS Tohoe 26 replaced the classic 16-tile volume HUD with a smaller one that appears only in the top-right corner of the active display.

The new HUD is hard to read at a glance, especially on multiple displays where the active screen might not be the one in use. It also lacks separate tiles, making precise volume adjustments challenging.

Due to varying volume levels across different websites, videos, and music, I often adjust the volume. I initially created VolumeGrid for personal use and have been using it since day one, iterating through versions and fixing edge cases. It is fully functional.

## License

Under the [MIT](LICENSE) License.
