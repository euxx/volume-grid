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
