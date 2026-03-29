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

    /// Lower bound of the AGC comfort zone (perceived RMS; too quiet below this → AGC raises volume).
    @Published var targetRMSLow: Float {
        didSet {
            let clamped = max(1e-5, min(targetRMSLow, 0.30))
            if targetRMSLow != clamped { targetRMSLow = clamped }
            // Enforce ordering: low must not exceed high.
            if targetRMSLow > targetRMSHigh { targetRMSHigh = targetRMSLow }
            writeIfNeeded(targetRMSLow, forKey: Keys.targetRMSLow)
        }
    }

    /// Upper bound of the AGC comfort zone (perceived RMS; too loud above this → AGC lowers volume).
    @Published var targetRMSHigh: Float {
        didSet {
            let clamped = max(1e-5, min(targetRMSHigh, 0.30))
            if targetRMSHigh != clamped { targetRMSHigh = clamped }
            // Enforce ordering: high must not fall below low.
            if targetRMSHigh < targetRMSLow { targetRMSLow = targetRMSHigh }
            writeIfNeeded(targetRMSHigh, forKey: Keys.targetRMSHigh)
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

    // MARK: - Per-device calibration

    /// Stores a `[targetRMSLow, targetRMSHigh]` comfort zone calibrated on a specific
    /// output device.  Keyed by the CoreAudio device UID.  When Smart Volume starts or
    /// the output device changes, the coordinator loads the matching entry so the AGC
    /// immediately uses the previously calibrated zone for that device.
    struct DeviceCalibration: Codable, Equatable {
        var targetRMSLow: Float
        var targetRMSHigh: Float
    }

    /// Per-device calibration map.  Not `@Published` — changes are made via
    /// `saveCalibration(for:)` which writes to UserDefaults directly.
    private(set) var deviceCalibrations: [String: DeviceCalibration] = [:]

    /// Save a calibration entry for the given device UID and persist to UserDefaults.
    func saveCalibration(_ cal: DeviceCalibration, forDeviceUID uid: String) {
        deviceCalibrations[uid] = cal
        guard let data = try? JSONEncoder().encode(deviceCalibrations) else { return }
        defaults.set(data, forKey: Keys.deviceCalibrations)
    }

    /// Return the stored calibration for a device UID, or `nil` if none exists.
    func calibration(forDeviceUID uid: String) -> DeviceCalibration? {
        deviceCalibrations[uid]
    }

    private enum Keys {
        static let isEnabled = "smartVolume.isEnabled"
        static let targetRMSLow = "smartVolume.targetRMSLow"
        static let targetRMSHigh = "smartVolume.targetRMSHigh"
        static let minVolume = "smartVolume.minVolume"
        static let maxVolume = "smartVolume.maxVolume"
        static let smoothing = "smartVolume.smoothing"
        static let strength = "smartVolume.strength"
        static let deviceCalibrations = "smartVolume.deviceCalibrations"
        // Written once when the dead-zone model is first used; guards against
        // applying migrations more than once on subsequent launches.
        static let rmsVersion = "smartVolume.rmsVersion"
    }

    /// Version tag written to UserDefaults to mark that zone bounds are in use.
    private static let currentRMSVersion = "deadzone_v1"

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.deviceCalibrations),
            let decoded = try? JSONDecoder().decode(
                [String: DeviceCalibration].self, from: data)
        {
            deviceCalibrations = decoded
        }
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        targetRMSLow =
            defaults.object(forKey: Keys.targetRMSLow).map { _ in
                defaults.float(forKey: Keys.targetRMSLow)
            } ?? 0.020
        targetRMSHigh =
            defaults.object(forKey: Keys.targetRMSHigh).map { _ in
                defaults.float(forKey: Keys.targetRMSHigh)
            } ?? 0.090
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

        // Migration: reset any pre-dead-zone persisted values to new defaults.
        let storedVersion = defaults.string(forKey: Keys.rmsVersion) ?? ""
        if storedVersion != SmartVolumeSettings.currentRMSVersion {
            targetRMSLow = 0.020
            targetRMSHigh = 0.090
            defaults.set(Float(0.020), forKey: Keys.targetRMSLow)
            defaults.set(Float(0.090), forKey: Keys.targetRMSHigh)
            defaults.set(SmartVolumeSettings.currentRMSVersion, forKey: Keys.rmsVersion)
        }

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

        let newTargetRMSLow =
            defaults.object(forKey: Keys.targetRMSLow)
            .map { _ in defaults.float(forKey: Keys.targetRMSLow) } ?? 0.020
        if targetRMSLow != newTargetRMSLow { targetRMSLow = newTargetRMSLow }

        let newTargetRMSHigh =
            defaults.object(forKey: Keys.targetRMSHigh)
            .map { _ in defaults.float(forKey: Keys.targetRMSHigh) } ?? 0.090
        if targetRMSHigh != newTargetRMSHigh { targetRMSHigh = newTargetRMSHigh }

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

        if let data = defaults.data(forKey: Keys.deviceCalibrations),
            let decoded = try? JSONDecoder().decode(
                [String: DeviceCalibration].self, from: data)
        {
            deviceCalibrations = decoded
        } else {
            // Key was removed or corrupted externally — clear stale in-memory entries.
            deviceCalibrations = [:]
        }

    }
}
