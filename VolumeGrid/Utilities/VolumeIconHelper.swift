import AppKit

/// Shared helper that maps volume percentage to appropriate speaker icon and size.
enum VolumeIconHelper {
    struct VolumeIcon {
        let symbolName: String
        let size: CGFloat
    }

    /// Returns the appropriate speaker icon based on volume state.
    /// - Parameters:
    ///   - percentage: Volume percentage (0-100)
    ///   - isMuted: Whether the device is muted
    ///   - isUnsupported: Whether volume control is unsupported for this device
    /// - Returns: A VolumeIcon with the appropriate symbol name and size
    static func icon(
        for percentage: Int,
        isMuted: Bool = false,
        isUnsupported: Bool = false
    ) -> VolumeIcon {
        let clamped = max(0, min(percentage, 100))

        if isUnsupported {
            return VolumeIcon(symbolName: "nosign", size: 30)
        }

        if isMuted || clamped == 0 {
            return VolumeIcon(symbolName: "speaker.slash", size: 15)
        } else if clamped < 33 {
            return VolumeIcon(symbolName: "speaker.wave.1", size: 17)
        } else if clamped < 66 {
            return VolumeIcon(symbolName: "speaker.wave.2", size: 19)
        } else {
            return VolumeIcon(symbolName: "speaker.wave.3", size: 21)
        }
    }

    /// Returns the appropriate speaker icon for HUD display with larger sizes.
    /// - Parameters:
    ///   - percentage: Volume percentage (0-100)
    ///   - isMuted: Whether the device is muted
    ///   - isUnsupported: Whether volume control is unsupported for this device
    /// - Returns: A VolumeIcon with the appropriate symbol name and size for HUD display
    static func hudIcon(
        for percentage: Int,
        isMuted: Bool = false,
        isUnsupported: Bool = false
    ) -> VolumeIcon {
        let clamped = max(0, min(percentage, 100))

        if isUnsupported {
            return VolumeIcon(symbolName: "nosign", size: 30)
        }

        if isMuted || clamped == 0 {
            return VolumeIcon(symbolName: "speaker.slash.fill", size: 32)
        } else if clamped < 33 {
            return VolumeIcon(symbolName: "speaker.wave.1.fill", size: 36)
        } else if clamped < 66 {
            return VolumeIcon(symbolName: "speaker.wave.2.fill", size: 41)
        } else {
            return VolumeIcon(symbolName: "speaker.wave.3.fill", size: 47)
        }
    }
}
