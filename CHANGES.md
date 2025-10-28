# Release Notes

## Latest Update v2.4 - 2025-10-25

### UI Improvements

- **Progress bar background color**: switched to a translucent gray (30% opacity) to separate it from the fill color.
- The progress bar now makes volume changes and levels easier to read at a glance.

## Latest Update v2.3 - 2025-10-25

### UI Improvements

- **Progress bar color**: changed from blue to gray for a more understated look.
- Updated the colors for both the menu bar indicator and the in-menu progress bar.

## Latest Update v2.2 - 2025-10-25

### UI Improvements

- **Menu bar icon width**: reduced from 30pt to 20pt to match the speaker glyph.
- **Centered layout**: the speaker glyph and progress bar are now horizontally centered.
- **Compact design**: the item consumes less menu bar space for a more balanced appearance.

## Latest Update v2.1 - 2025-10-25

### UI Improvements

- **Progress bar length**: reduced from 44pt to 14pt for a tighter look.
- **Menu bar item width**: reduced from 60pt to 30pt to save space.

## Feature Update v2.0

### Menu Bar Volume Progress Indicator

The menu bar now shows a slim progress indicator directly beneath the speaker icon, updating in real time while keeping the detailed volume information inside the menu.

#### Detailed Changes

1. **Progress indicator beneath the menu bar icon (NEW):**
   - Placement: directly under the speaker icon.
  - Appearance: 2pt tall with a light gray track and dark gray fill.
  - Width: 14pt, updated dynamically based on the volume percentage (0-100%).
  - Responsiveness: real time with no delay.

2. **Detailed volume info in the menu (RETAINED):**
   - Keeps the original in-menu view (progress bar + percentage text).
   - View the details by clicking the menu bar icon.

#### Visual Example

```
Menu bar example:
┌─────────────────┐
│ 🔊              │  ← Icon
│ ────────        │  ← New indicator (shows 50% volume)
└─────────────────┘

Menu after click:
[Menu]
  ├─ Current Volume: 50%
  │  [██████░░░░░░░░] ← Detailed progress bar
  │
  ├─ Current Device: Built-in Speaker
  ├─ ────────────
  ├─ Launch at Login ☑
  ├─ ────────────
  └─ Quit
```

#### Code Locations

- **File**: `VolumeGridApp.swift`
- **New method**: `createStatusBarCustomView(percentage: Int) -> NSView`
  - Builds the custom menu bar view with the icon and progress indicator.

- **Updated methods:**
  - `setupStatusBarItem()`: now initializes the custom view instead of a plain icon.
  - Volume subscription block: updates both the menu bar indicator and the in-menu details simultaneously.

- **Removed method:**
  - `updateStatusBarIcon()`: replaced by the custom view approach.

#### Technical Notes

- Menu bar item width set to 20pt to match the icon.
- Speaker icon and progress bar remain horizontally centered.
- Reacts to volume changes instantly with no debounce delay.
- Automatically adapts to dark and light system themes.

## Build Status

✅ Build succeeded.

## Next Steps

1. Double-click `/tmp/volumegrid-build/Build/Products/Debug/VolumeGrid.app` to launch the app.
2. Or run: `open /tmp/volumegrid-build/Build/Products/Debug/VolumeGrid.app`
3. Adjust the system volume to see the menu bar indicator update.
4. Click the menu bar icon to view detailed information.
