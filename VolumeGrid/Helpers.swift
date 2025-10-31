import AppKit
import CoreGraphics
import Foundation

/// Shared helper that normalizes how the app formats volume values.
enum VolumeFormatter {
    private static let blocksCount: CGFloat = 16.0
    private static let quarterStep: CGFloat = 0.25
    private static let epsilon: CGFloat = 0.001

    static func formattedVolumeString(for percentage: Int) -> String {
        let clamped = max(0, min(percentage, 100))
        return formattedVolumeString(forScalar: CGFloat(clamped) / 100.0)
    }

    static func formattedVolumeString(forScalar scalar: CGFloat) -> String {
        let totalBlocks = max(0, min(scalar, 1)) * blocksCount
        let quarterBlocks = (totalBlocks / quarterStep).rounded() * quarterStep
        return formatVolumeCount(quarterBlocks: quarterBlocks)
    }

    static func formatVolumeCount(quarterBlocks value: CGFloat) -> String {
        let integerPart = Int(value)
        let fractionalPart = value - CGFloat(integerPart)

        if fractionalPart < epsilon {
            return "\(integerPart)"
        }

        if abs(fractionalPart - 1.0) < epsilon {
            return "\(integerPart + 1)"
        }

        let fractionString: String
        switch fractionalPart {
        case (quarterStep - epsilon)...(quarterStep + epsilon):
            fractionString = "1/4"
        case (0.5 - epsilon)...(0.5 + epsilon):
            fractionString = "2/4"
        case (0.75 - epsilon)...(0.75 + epsilon):
            fractionString = "3/4"
        default:
            fractionString = String(format: "%.2f", fractionalPart)
        }

        if integerPart == 0 {
            return fractionString
        } else {
            return "\(integerPart)+\(fractionString)"
        }
    }
}

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
