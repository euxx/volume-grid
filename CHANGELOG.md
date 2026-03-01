# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.2.0] - 2026-03-01

### Fixes

- Fix key-press debounce race condition, volume element detection, SystemEventMonitor cleanup, device menu unnecessary rebuilds, and device switch error alert title
- Fix SystemEventMonitor data race: global monitor callback dispatched to MainActor
- Fix SystemEventMonitor deinit: synchronize monitor removal on main thread
- Eliminate all MainActor.assumeIsolated: use Task { @MainActor in } for completion handlers and animation callbacks

### Improvements

- Upgrade to Swift 6 language mode with strict concurrency checking
- Refactoring: consolidate ThreadSafeProperty, remove redundant code paths and unused abstractions, improve naming
- Concurrency: enable warnings-as-errors, mark pure types Sendable/nonisolated, use OSAllocatedUnfairLock(initialState:) for compiler-checked locking
- Tests: add SPM test target, skip hardware-dependent tests, clean up mocks, add dispatchPrecondition and assertForOverFulfill
- Formatting and documentation

## [1.1.1] - 2026-02-27

### Fixes

- Fix HUD window double-release crash on screen configuration changes
- Fix race condition in VolumeMonitor listener cleanup causing listener leaks on device switch
- Disable implicit CALayer animations in volume blocks for instant visual updates
- Cancel in-flight fade-out animation when showing HUD to prevent flicker
- Sort output devices by name length (shortest first)

### Improvements

- Add `@MainActor` to StatusBarController for stricter concurrency safety
- Reuse VolumeMonitor's AudioDeviceManager for device switching

## [1.1.0] - 2025-12-12

### Features

- Add ability to switch sound output devices from the menu bar icon's menu

### Improvements

- Enhance progress bar appearance with dynamic colors for light/dark modes

### Fixes

- Update volumeScalar handling in VolumeMonitor for accurate state management

## [1.0.0] - 2025-11-30

- 🔲 Classic 16-tile volume HUD with quarter-tile precision
- 🎧 Shows the sound output device and numeric volume on volume HUD
- 🖥️ Shows volume HUD on all displays
- 🔄 Shows volume HUD when switching sound output devices
- 🔊 Menu bar icon with subtle progress bar that changes with volume
- 🛠️ Native, minimal, lightweight (~2MB app, ~20MB RAM)
