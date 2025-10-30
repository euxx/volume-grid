import CoreGraphics
import Foundation

/// Encapsulates the data required to render the on-screen volume HUD.
struct VolumeHUDContext {
    let volumeScalar: CGFloat
    let deviceName: String?
    let isMuted: Bool
    let isUnsupported: Bool
}
