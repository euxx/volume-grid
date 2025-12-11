import AppKit
import CoreGraphics

enum VolumeGridConstants {
    /// Total number of volume blocks
    static let volumeBlocksCount: Int = 16

    enum Icons {
        static let sizeStatusBar: CGFloat = 15
        static let sizeLow: CGFloat = 17
        static let sizeMedium: CGFloat = 19
        static let sizeHigh: CGFloat = 21
        static let sizeHUDMuted: CGFloat = 32
        static let sizeHUDLow: CGFloat = 36
        static let sizeHUDMedium: CGFloat = 41
        static let sizeHUDHigh: CGFloat = 47
        static let sizeUnsupported: CGFloat = 30
    }

    enum Audio {
        /// Tolerance for comparing volume values to avoid floating-point precision issues
        static let volumeEpsilon: CGFloat = 0.001

        /// Volume step size (1/4 of a block)
        static let quarterStep: CGFloat = 0.25

        /// Debounce delay for volume change events (in seconds)
        static let volumeChangeDebounceDelay: TimeInterval = 0.05

        /// Debounce delay for audio device change events (in seconds)
        static let deviceChangeDebounceDelay: TimeInterval = 0.1

        /// Icon size thresholds for volume level (0-33%, 33-66%, 66-100%)
        static let volumeLevelLow: Int = 33
        static let volumeLevelMedium: Int = 66
    }

    enum HUD {
        static let width: CGFloat = 240
        static let height: CGFloat = 160
        static let alpha: CGFloat = 0.97
        static let displayDuration: TimeInterval = 1.4
        static let cornerRadius: CGFloat = 20
        static let marginX: CGFloat = 10
        static let minVerticalPadding: CGFloat = 14
        static let fadeInDuration: TimeInterval = 0.3
        static let fadeOutDuration: TimeInterval = 0.6
        static let textFont = NSFont.systemFont(ofSize: 12)

        enum Layout {
            static let iconSize: CGFloat = 40
            static let spacingIconToDevice: CGFloat = 16
            static let spacingDeviceToBlocks: CGFloat = 24
            static let spacingIconToDeviceUnsupported: CGFloat = 20
            static let spacingDeviceToBlocksUnsupported: CGFloat = 0
            static let leadingSpacerWidth: CGFloat = 30
            static let textStackSpacing: CGFloat = 8
            static let volumeLabelWidthPadding: CGFloat = 6
        }

        enum VolumeBlocksView {
            static let blockWidth: CGFloat = 10
            static let blockHeight: CGFloat = 6
            static let blockSpacing: CGFloat = 1
            static let cornerRadius: CGFloat = 0.5
            static let inactiveBlockColor = NSColor(
                red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 0.5
            )
        }
    }

    enum StatusBar {
        static let maxProgressBarWidth: CGFloat = 6
        static let progressBarBackgroundColor = NSColor.systemGray.withAlphaComponent(0.6)
        static let progressBarFillColor = NSColor.gray
    }

    enum System {
        static let minimumMacOSVersion = "14.0"
    }
}
