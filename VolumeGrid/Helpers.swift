import AppKit
import CoreGraphics
import Foundation

let volumeEpsilon: CGFloat = 0.001

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum VolumeFormatter {
    private static let blocksCount: CGFloat = 16.0
    private static let quarterStep: CGFloat = 0.25

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

        if fractionalPart < volumeEpsilon {
            return "\(integerPart)"
        }
        if fractionalPart > 1.0 - volumeEpsilon {
            return "\(integerPart + 1)"
        }

        let fractionString: String
        switch fractionalPart {
        case quarterStep - volumeEpsilon...quarterStep + volumeEpsilon:
            fractionString = "1/4"
        case 0.5 - volumeEpsilon...0.5 + volumeEpsilon:
            fractionString = "2/4"
        case 0.75 - volumeEpsilon...0.75 + volumeEpsilon:
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

        if isUnsupported {
            return VolumeIcon(symbolName: "nosign", size: 30)
        }

        if clamped == 0 {
            let size: CGFloat = forHUD ? 32 : 15
            let symbolName = forHUD ? "speaker.slash.fill" : "speaker.slash"
            return VolumeIcon(symbolName: symbolName, size: size)
        }

        switch clamped {
        case 0..<33:
            let size: CGFloat = forHUD ? 36 : 17
            let symbolName = forHUD ? "speaker.wave.1.fill" : "speaker.wave.1"
            return VolumeIcon(symbolName: symbolName, size: size)
        case 33..<66:
            let size: CGFloat = forHUD ? 41 : 19
            let symbolName = forHUD ? "speaker.wave.2.fill" : "speaker.wave.2"
            return VolumeIcon(symbolName: symbolName, size: size)
        default:
            let size: CGFloat = forHUD ? 47 : 21
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
