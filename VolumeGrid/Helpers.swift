import AppKit
import CoreGraphics
import Foundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum VolumeFormatter {
    private static let blocksCount = VolumeGridConstants.Audio.blocksCount
    static let quarterStep = VolumeGridConstants.Audio.quarterStep

    static func formattedVolumeString(for percentage: Int) -> String {
        let clamped = percentage.clamped(to: 0...100)
        return formattedVolumeString(forScalar: CGFloat(clamped) / 100.0)
    }

    static func formattedVolumeString(forScalar scalar: CGFloat) -> String {
        let totalBlocks = scalar.clamped(to: 0...1) * blocksCount
        let quarterBlocks = (totalBlocks / quarterStep).rounded() * quarterStep
        return formatVolumeCount(quarterBlocks: quarterBlocks)
    }

    static func formatVolumeCount(quarterBlocks value: CGFloat) -> String {
        let integerPart = Int(value)
        let fractionalPart = value - CGFloat(integerPart)
        let epsilon = VolumeGridConstants.Audio.volumeEpsilon

        if fractionalPart < epsilon {
            return "\(integerPart)"
        }
        if fractionalPart > 1.0 - epsilon {
            return "\(integerPart + 1)"
        }

        let fractionString: String
        switch fractionalPart {
        case quarterStep - epsilon...quarterStep + epsilon:
            fractionString = "1/4"
        case 0.5 - epsilon...0.5 + epsilon:
            fractionString = "2/4"
        case 0.75 - epsilon...0.75 + epsilon:
            fractionString = "3/4"
        default:
            fractionString = String(format: "%.2f", fractionalPart)
        }

        return integerPart == 0 ? fractionString : "\(integerPart)+\(fractionString)"
    }
}

enum VolumeIconHelper {
    struct VolumeIcon {
        let symbolName: String
        let size: CGFloat
    }

    static func icon(
        for percentage: Int,
        isUnsupported: Bool = false,
        forHUD: Bool = false
    ) -> VolumeIcon {
        let clamped = percentage.clamped(to: 0...100)
        let lowThreshold = VolumeGridConstants.Audio.volumeLevelLow
        let mediumThreshold = VolumeGridConstants.Audio.volumeLevelMedium

        if isUnsupported {
            return VolumeIcon(
                symbolName: "nosign",
                size: VolumeGridConstants.HUD.Icons.sizeUnsupported
            )
        }

        if clamped == 0 {
            let size: CGFloat =
                forHUD
                ? VolumeGridConstants.HUD.Icons.sizeHUDMuted
                : VolumeGridConstants.HUD.Icons.sizeStatusBar
            let symbolName = forHUD ? "speaker.slash.fill" : "speaker.slash"
            return VolumeIcon(symbolName: symbolName, size: size)
        }

        switch clamped {
        case 0..<lowThreshold:
            let size: CGFloat =
                forHUD
                ? VolumeGridConstants.HUD.Icons.sizeHUDLow
                : VolumeGridConstants.HUD.Icons.sizeLow
            let symbolName = forHUD ? "speaker.wave.1.fill" : "speaker.wave.1"
            return VolumeIcon(symbolName: symbolName, size: size)
        case lowThreshold..<mediumThreshold:
            let size: CGFloat =
                forHUD
                ? VolumeGridConstants.HUD.Icons.sizeHUDMedium
                : VolumeGridConstants.HUD.Icons.sizeMedium
            let symbolName = forHUD ? "speaker.wave.2.fill" : "speaker.wave.2"
            return VolumeIcon(symbolName: symbolName, size: size)
        default:
            let size: CGFloat =
                forHUD
                ? VolumeGridConstants.HUD.Icons.sizeHUDHigh
                : VolumeGridConstants.HUD.Icons.sizeHigh
            let symbolName = forHUD ? "speaker.wave.3.fill" : "speaker.wave.3"
            return VolumeIcon(symbolName: symbolName, size: size)
        }
    }

    static func hudIcon(
        for percentage: Int,
        isUnsupported: Bool = false
    ) -> VolumeIcon {
        icon(for: percentage, isUnsupported: isUnsupported, forHUD: true)
    }
}
