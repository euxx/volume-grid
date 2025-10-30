import AppKit
import Combine

/// Bridges volume monitor HUD events to the concrete HUD rendering implementation.
final class HUDController {
    private let hudManager = HUDManager()
    private var hudSubscription: AnyCancellable?

    init(volumeMonitor: VolumeMonitor) {
        hudSubscription = volumeMonitor.hudEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] context in
                self?.hudManager.showHUD(
                    volumeScalar: context.volumeScalar,
                    deviceName: context.deviceName,
                    isMuted: context.isMuted,
                    isUnsupported: context.isUnsupported
                )
            }
    }
}
