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

    // MARK: - Speech profile
    //
    // When SoundAnalysis detects speech, the coordinator switches to these settings
    // so the AGC doesn't boost volume to maximum for naturally quiet voices.

    /// Target RMS for speech content.  Higher than the default music target so the AGC
    /// requires less volume boost for quiet voices.
    @Published var speechTargetRMS: Float {
        didSet {
            let clamped = max(0.01, min(speechTargetRMS, 0.30))
            if speechTargetRMS != clamped { speechTargetRMS = clamped }
            writeIfNeeded(speechTargetRMS, forKey: Keys.speechTargetRMS)
        }
    }

    // MARK: - Per-device calibration

    /// Stores a `targetRMS`/`speechTargetRMS` pair calibrated on a specific output device.
    /// Keyed by the device UID returned by CoreAudio.  When Smart Volume starts or the
    /// output device changes, the coordinator loads the matching entry so the AGC
    /// immediately uses the previously calibrated loudness target for that device.
    struct DeviceCalibration: Codable, Equatable {
        var targetRMS: Float
        var speechTargetRMS: Float
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
        static let targetRMS = "smartVolume.targetRMS"
        static let minVolume = "smartVolume.minVolume"
        static let maxVolume = "smartVolume.maxVolume"
        static let smoothing = "smartVolume.smoothing"
        static let strength = "smartVolume.strength"
        static let speechTargetRMS = "smartVolume.speechTargetRMS"
        static let deviceCalibrations = "smartVolume.deviceCalibrations"
        // Written once when K-weighted measurement is first used; guards against
        // applying the migration factor more than once on subsequent launches.
        static let rmsVersion = "smartVolume.rmsVersion"
    }

    /// Version tag written to UserDefaults to mark that targetRMS values are in the
    /// perceived-loudness scale (measuredRMS × systemVolume).
    private static let currentRMSVersion = "kweighted_perceived_v2"

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.deviceCalibrations),
            let decoded = try? JSONDecoder().decode(
                [String: DeviceCalibration].self, from: data)
        {
            deviceCalibrations = decoded
        }
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        targetRMS =
            defaults.object(forKey: Keys.targetRMS).map { _ in
                defaults.float(forKey: Keys.targetRMS)
            } ?? 0.040  // perceived-loudness default: typical comfortable speech/video
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

        let rawSpeechTargetRMS =
            defaults.object(forKey: Keys.speechTargetRMS).map { _ in
                defaults.float(forKey: Keys.speechTargetRMS)
            } ?? 0.055  // higher than music/ambient 0.040: less AGC reduction on loud speech
        speechTargetRMS = max(0.01, min(rawSpeechTargetRMS, 0.30))

        // Migration: update targetRMS / speechTargetRMS to the current semantic scale.
        // Versions that start with "kweighted_perceived_" are already in perceived-loudness
        // space; we only reset to defaults when upgrading from a pre-perceived-RMS version.
        let storedVersion = defaults.string(forKey: Keys.rmsVersion) ?? ""
        if storedVersion != SmartVolumeSettings.currentRMSVersion {
            if !storedVersion.hasPrefix("kweighted_perceived_") {
                // Legacy (plain-RMS or K-weighted pre-volume) scale: reset to new defaults.
                // Users can press Calibrate to personalise after the upgrade.
                targetRMS = 0.040
                speechTargetRMS = 0.055
                defaults.set(Float(0.040), forKey: Keys.targetRMS)
                defaults.set(Float(0.055), forKey: Keys.speechTargetRMS)
            }
            // Always stamp the current version so this block does not re-run.
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

        let newTargetRMS =
            defaults.object(forKey: Keys.targetRMS)
            .map { _ in defaults.float(forKey: Keys.targetRMS) } ?? 0.040
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

        let rawSpeechTarget =
            defaults.object(forKey: Keys.speechTargetRMS)
            .map { _ in defaults.float(forKey: Keys.speechTargetRMS) } ?? 0.055
        let newSpeechTarget = max(0.01, min(rawSpeechTarget, 0.30))
        if speechTargetRMS != newSpeechTarget { speechTargetRMS = newSpeechTarget }

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
