import AppKit
import CoreGraphics

enum VolumeGridConstants {
    /// Total number of volume blocks
    nonisolated static let volumeBlocksCount: Int = 16

    enum Icons {
        nonisolated static let sizeStatusBar: CGFloat = 15
        nonisolated static let sizeLow: CGFloat = 17
        nonisolated static let sizeMedium: CGFloat = 19
        nonisolated static let sizeHigh: CGFloat = 21
        nonisolated static let sizeHUDMuted: CGFloat = 32
        nonisolated static let sizeHUDLow: CGFloat = 36
        nonisolated static let sizeHUDMedium: CGFloat = 41
        nonisolated static let sizeHUDHigh: CGFloat = 47
        nonisolated static let sizeUnsupported: CGFloat = 30
    }

    enum Audio {
        /// Tolerance for comparing volume values to avoid floating-point precision issues
        nonisolated static let volumeEpsilon: CGFloat = 0.001

        /// Volume step size (1/4 of a block)
        nonisolated static let quarterStep: CGFloat = 0.25

        /// Debounce delay for volume change events (in seconds)
        nonisolated static let volumeChangeDebounceDelay: TimeInterval = 0.05

        /// Debounce delay for audio device change events (in seconds)
        nonisolated static let deviceChangeDebounceDelay: TimeInterval = 0.1

        /// Icon size thresholds for volume level (0-33%, 33-66%, 66-100%)
        nonisolated static let volumeLevelLow: Int = 33
        nonisolated static let volumeLevelMedium: Int = 66
    }

    enum HUD {
        nonisolated static let width: CGFloat = 240
        nonisolated static let height: CGFloat = 160
        nonisolated static let alpha: CGFloat = 0.97
        nonisolated static let displayDuration: TimeInterval = 1.4
        nonisolated static let cornerRadius: CGFloat = 20
        nonisolated static let marginX: CGFloat = 10
        nonisolated static let minVerticalPadding: CGFloat = 14
        nonisolated static let fadeInDuration: TimeInterval = 0.3
        nonisolated static let fadeOutDuration: TimeInterval = 0.6
        static let textFont = NSFont.systemFont(ofSize: 12)

        enum Layout {
            nonisolated static let iconSize: CGFloat = 40
            nonisolated static let spacingIconToDevice: CGFloat = 16
            nonisolated static let spacingDeviceToBlocks: CGFloat = 24
            nonisolated static let spacingIconToDeviceUnsupported: CGFloat = 20
            nonisolated static let spacingDeviceToBlocksUnsupported: CGFloat = 0
            nonisolated static let leadingSpacerWidth: CGFloat = 30
            nonisolated static let textStackSpacing: CGFloat = 8
            nonisolated static let volumeLabelWidthPadding: CGFloat = 6
        }

        enum VolumeBlocksView {
            nonisolated static let blockWidth: CGFloat = 10
            nonisolated static let blockHeight: CGFloat = 6
            nonisolated static let blockSpacing: CGFloat = 1
            nonisolated static let cornerRadius: CGFloat = 0.5
            static let inactiveBlockColor: NSColor = NSColor.black.withAlphaComponent(0.3)
        }
    }

    enum StatusBar {
        nonisolated static let maxProgressBarWidth: CGFloat = 6
        static let progressBarBackgroundColor: NSColor = NSColor.systemGray.withAlphaComponent(0.6)
        static let progressBarFillColor: NSColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white.withAlphaComponent(0.6)
            } else {
                return NSColor.black.withAlphaComponent(0.6)
            }
        }
        static let menuProgressBarBackgroundColor: NSColor = NSColor.controlBackgroundColor
        static let menuProgressBarFillColor: NSColor = NSColor.white.withAlphaComponent(0.6)
        static let menuProgressBarThumbColor: NSColor = NSColor.white
    }
}
