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

        let fractionMap: [(range: ClosedRange<CGFloat>, string: String)] = [
            ((quarterStep - epsilon)...(quarterStep + epsilon), "1/4"),
            ((0.5 - epsilon)...(0.5 + epsilon), "2/4"),
            ((0.75 - epsilon)...(0.75 + epsilon), "3/4"),
        ]

        let fractionString =
            fractionMap.first { $0.range.contains(fractionalPart) }?.string
            ?? String(format: "%.2f", fractionalPart)

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
    ///   - forHUD: Whether to use larger sizes for HUD display
    /// - Returns: A VolumeIcon with the appropriate symbol name and size
    static func icon(
        for percentage: Int,
        isMuted: Bool = false,
        isUnsupported: Bool = false,
        forHUD: Bool = false
    ) -> VolumeIcon {
        let clamped = max(0, min(percentage, 100))

        if isUnsupported {
            return VolumeIcon(symbolName: "nosign", size: 30)
        }

        if isMuted || clamped == 0 {
            let size: CGFloat = forHUD ? 32 : 15
            let symbolName = forHUD ? "speaker.slash.fill" : "speaker.slash"
            return VolumeIcon(symbolName: symbolName, size: size)
        } else if clamped < 33 {
            let size: CGFloat = forHUD ? 36 : 17
            let symbolName = forHUD ? "speaker.wave.1.fill" : "speaker.wave.1"
            return VolumeIcon(symbolName: symbolName, size: size)
        } else if clamped < 66 {
            let size: CGFloat = forHUD ? 41 : 19
            let symbolName = forHUD ? "speaker.wave.2.fill" : "speaker.wave.2"
            return VolumeIcon(symbolName: symbolName, size: size)
        } else {
            let size: CGFloat = forHUD ? 47 : 21
            let symbolName = forHUD ? "speaker.wave.3.fill" : "speaker.wave.3"
            return VolumeIcon(symbolName: symbolName, size: size)
        }
    }

    /// Convenience method for HUD display with larger sizes.
    static func hudIcon(
        for percentage: Int,
        isMuted: Bool = false,
        isUnsupported: Bool = false
    ) -> VolumeIcon {
        icon(for: percentage, isMuted: isMuted, isUnsupported: isUnsupported, forHUD: true)
    }
}
