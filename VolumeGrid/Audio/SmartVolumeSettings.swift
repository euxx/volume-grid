import Combine
import Foundation

/// Persistent settings for Smart Volume, backed by UserDefaults.
final class SmartVolumeSettings: ObservableObject {
    static let shared = SmartVolumeSettings()

    private let defaults: UserDefaults
    private var isWritingDefaults = false

    @Published var isEnabled: Bool {
        didSet { writeIfNeeded(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var targetRMS: Float {
        didSet {
            let clamped = max(1e-5, min(targetRMS, 0.30))
            if targetRMS != clamped { targetRMS = clamped }
            writeIfNeeded(targetRMS, forKey: Keys.targetRMS)
        }
    }

    @Published var minVolume: Float {
        didSet {
            let clamped = max(0, min(minVolume, 1))
            if minVolume != clamped { minVolume = clamped }
            // Enforce minVolume <= maxVolume on every mutation path.
            if maxVolume < minVolume { maxVolume = minVolume }
            writeIfNeeded(minVolume, forKey: Keys.minVolume)
        }
    }

    @Published var maxVolume: Float {
        didSet {
            let clamped = max(0, min(maxVolume, 1))
            if maxVolume != clamped { maxVolume = clamped }
            // Enforce minVolume <= maxVolume on every mutation path.
            if minVolume > maxVolume { minVolume = maxVolume }
            writeIfNeeded(maxVolume, forKey: Keys.maxVolume)
        }
    }

    /// 0 = responsive (fast AGC), 1 = smooth (slow AGC). Default 0.3.
    @Published var smoothing: Float {
        didSet {
            let clamped = max(0, min(smoothing, 1))
            if smoothing != clamped { smoothing = clamped }
            writeIfNeeded(smoothing, forKey: Keys.smoothing)
        }
    }

    /// AGC correction strength. 1.0 = full normalisation; lower = gentler compression.
    @Published var strength: Float {
        didSet {
            let clamped = max(0, min(strength, 1))
            if strength != clamped { strength = clamped }
            writeIfNeeded(strength, forKey: Keys.strength)
        }
    }

    /// Attack time constant derived from `smoothing` (loud → reduce volume).
    var attackSeconds: Float { 0.5 + smoothing * (5.0 - 0.5) }
    /// Release time constant derived from `smoothing` (quiet → raise volume).
    /// Range: 3 s (smoothing=0) … 12 s (smoothing=1).
    var releaseSeconds: Float { 3.0 + smoothing * (12.0 - 3.0) }

    private enum Keys {
        static let isEnabled = "smartVolume.isEnabled"
        static let targetRMS = "smartVolume.targetRMS"
        static let minVolume = "smartVolume.minVolume"
        static let maxVolume = "smartVolume.maxVolume"
        static let smoothing = "smartVolume.smoothing"
        static let strength = "smartVolume.strength"
    }

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        targetRMS =
            defaults.object(forKey: Keys.targetRMS).map { _ in
                defaults.float(forKey: Keys.targetRMS)
            } ?? 0.05
        let rawMin =
            defaults.object(forKey: Keys.minVolume).map { _ in
                defaults.float(forKey: Keys.minVolume)
            } ?? 0.1
        let rawMax =
            defaults.object(forKey: Keys.maxVolume).map { _ in
                defaults.float(forKey: Keys.maxVolume)
            } ?? 1.0
        // Enforce minVolume <= maxVolume: clamp max to [resolvedMin, 1].
        let resolvedMin = max(0, min(rawMin, 1))
        minVolume = resolvedMin
        maxVolume = max(resolvedMin, min(rawMax, 1))
        let rawSmoothing =
            defaults.object(forKey: Keys.smoothing).map { _ in
                defaults.float(forKey: Keys.smoothing)
            } ?? 0.3
        smoothing = max(0, min(rawSmoothing, 1))
        let rawStrength =
            defaults.object(forKey: Keys.strength).map { _ in
                defaults.float(forKey: Keys.strength)
            } ?? 1.0
        strength = max(0, min(rawStrength, 1))

        // Watch for changes from external tools (e.g. `defaults write`) so the running
        // app picks them up immediately without a restart.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadFromDefaults() }
        }
    }

    // MARK: - Private helpers

    private func writeIfNeeded<T>(_ value: T, forKey key: String) {
        guard !isWritingDefaults else { return }
        defaults.set(value, forKey: key)
    }

    private func reloadFromDefaults() {
        isWritingDefaults = true
        defer { isWritingDefaults = false }

        let newIsEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        if isEnabled != newIsEnabled { isEnabled = newIsEnabled }

        let newTargetRMS =
            defaults.object(forKey: Keys.targetRMS)
            .map { _ in defaults.float(forKey: Keys.targetRMS) } ?? 0.05
        if targetRMS != newTargetRMS { targetRMS = newTargetRMS }

        let rawMin =
            defaults.object(forKey: Keys.minVolume)
            .map { _ in defaults.float(forKey: Keys.minVolume) } ?? 0.1
        let newMin = max(0, min(rawMin, 1))
        if minVolume != newMin { minVolume = newMin }

        let rawMax =
            defaults.object(forKey: Keys.maxVolume)
            .map { _ in defaults.float(forKey: Keys.maxVolume) } ?? 1.0
        // Enforce minVolume <= maxVolume: clamp max to [resolved min, 1].
        let newMax = max(newMin, min(rawMax, 1))
        if maxVolume != newMax { maxVolume = newMax }

        let rawSmoothing =
            defaults.object(forKey: Keys.smoothing)
            .map { _ in defaults.float(forKey: Keys.smoothing) } ?? 0.3
        let newSmoothing = max(0, min(rawSmoothing, 1))
        if smoothing != newSmoothing { smoothing = newSmoothing }

        let rawStrength =
            defaults.object(forKey: Keys.strength)
            .map { _ in defaults.float(forKey: Keys.strength) } ?? 1.0
        let newStrength = max(0, min(rawStrength, 1))
        if strength != newStrength { strength = newStrength }
    }
}
