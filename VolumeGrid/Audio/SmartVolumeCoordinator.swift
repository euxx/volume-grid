import AVFoundation
import Combine
import Dispatch
import Foundation
import os.log

/// Pure description of the effect a single volume key press should have on the AGC settings.
///
/// - At ceiling (current ≥ activeMax − step/2): ceiling shifts; zone bounds unchanged.
/// - Mid-range: ceiling stays; dead zone is recentred around the user's intended volume.
/// - `seedVolume`: volume passed to `LoudnessNormalizer.resetWith(currentVolume:)` so the
///   AGC settles at the new intended level without a transient jump.
struct VolumeKeyEffect {
    let newMax: Float?  // nil = ceiling unchanged
    let seedVolume: Float  // always set; used to reseed normalizer

    static func compute(
        up: Bool,
        currentVolume: Float,
        activeMax: Float,
        minVolume: Float
    ) -> VolumeKeyEffect {
        let step = 1.0 / Float(VolumeGridConstants.volumeBlocksCount)
        if currentVolume >= activeMax - step / 2 {
            let newMax = up ? min(1.0, activeMax + step) : max(minVolume, activeMax - step)
            return .init(newMax: newMax, seedVolume: newMax)
        } else {
            let desiredVolume =
                up ? min(activeMax, currentVolume + step) : max(minVolume, currentVolume - step)
            return .init(newMax: nil, seedVolume: desiredVolume)
        }
    }
}

/// Coordinates AudioTapMonitor, LoudnessNormalizer, and VolumeMonitor to implement
/// dynamic loudness normalisation.  Runs entirely on @MainActor except for the
/// DispatchSourceTimer fire handler (nonisolated timerQueue).
@MainActor
final class SmartVolumeCoordinator: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    /// Live diagnostics — updated every AGC tick (nil when stopped or silent).
    @Published private(set) var lastMeasuredRMS: Float?
    /// The active comfort-zone bounds used by the normalizer.  Reflects per-device calibration
    /// when a calibrated device is running, otherwise mirrors the global settings values.
    @Published private(set) var activeTargetRMSLow: Float = SmartVolumeSettings.shared.targetRMSLow
    @Published private(set) var activeTargetRMSHigh: Float = SmartVolumeSettings.shared
        .targetRMSHigh
    /// Currently detected audio scene; nil when Smart Volume is not running or macOS < 14.2.
    @Published private(set) var currentScene: String?
    /// Live confidence scores from SoundAnalysis; 0 when classifier is inactive.
    @Published private(set) var speechConfidence: Double = 0
    @Published private(set) var musicConfidence: Double = 0
    /// Current system volume scalar (mirrors VolumeMonitor.volumeScalar for live UI updates).
    @Published private(set) var currentVolume: Double = 0

    private let volumeMonitor: VolumeMonitor
    private let deviceManager = AudioDeviceManager()
    private var normalizer = LoudnessNormalizer()  // struct with mutating methods — must be var
    private let settings = SmartVolumeSettings.shared

    // RMS pre-smoothing: asymmetric time constants so brief quiet patches (speech pauses)
    // don't immediately register as "content went quiet" and trigger a gain increase.
    // Rising (louder): fast — catch loud content quickly.
    // Falling (quieter): moderately slow — cushion brief pauses without delaying recovery.
    private let rmsRisingSeconds: Float = 0.3
    private let rmsFallingSeconds: Float = 1.5
    private var smoothedRMS: Float = 0.0

    // _tapMonitorBox holds an AudioTapMonitor (macOS 14.2+) without requiring
    // @available on every property that touches the coordinator.
    private var _tapMonitorBox: AnyObject?

    // _classifierBox holds a SoundSceneClassifier (macOS 12.0+) using the same pattern.
    private var _classifierBox: AnyObject?
    private var classifierCancellables = Set<AnyCancellable>()

    @available(macOS 14.2, *)
    private var tapMonitor: AudioTapMonitor? {
        get { _tapMonitorBox as? AudioTapMonitor }
        set { _tapMonitorBox = newValue }
    }

    @available(macOS 14.2, *)
    private var classifier: SoundSceneClassifier? {
        get { _classifierBox as? SoundSceneClassifier }
        set { _classifierBox = newValue }
    }

    private var smartVolumeTimer: DispatchSourceTimer?
    private nonisolated let timerQueue = DispatchQueue(
        label: "one.eux.volumegrid.smartvolume", qos: .userInitiated)

    /// AGC update interval (seconds).  Used for both the timer schedule and the IIR
    /// time-constant conversion.  Keep these two in sync via a single constant.
    private let timerInterval: Float = 0.2

    private var cancellables = Set<AnyCancellable>()
    /// Tracks previous mute state to detect the unmute edge in handleAGC.
    private var wasMuted = false
    /// Hysteresis counter for `lastMeasuredRMS` diagnostics.  Counts down after raw silence
    /// begins so brief speech pauses do not flicker the display to nil.
    private var diagHoldTicks = 0
    private let diagHoldThreshold = 3  // 3 × 200 ms = 600 ms hold after raw silence
    /// UID of the CoreAudio device the current tap is attached to.
    /// Stored so `calibrateTargetRMS()` can save the calibration to the right device entry.
    private var currentDeviceUID: String?
    /// Anticipated system volume after pending key presses, while CoreAudio has not yet
    /// updated `volumeMonitor.volumeScalar` (~50 ms lag).  Cleared 200 ms after the last
    /// key press so rapid successive presses accumulate correctly.
    private var pendingVolumeBase: Float?
    private var pendingVolumeTask: Task<Void, Never>?

    private let log = Logger(subsystem: "one.eux.volumegrid", category: "SmartVolume")

    init(volumeMonitor: VolumeMonitor) {
        self.volumeMonitor = volumeMonitor
        // Mirror current system volume for live UI readout.
        volumeMonitor.$volumeScalar
            .map { Double($0) }
            .assign(to: &$currentVolume)
        // Rebuild the tap whenever the default output device changes.
        volumeMonitor.$currentDevice
            .dropFirst()
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] _ in self?.rebuildTapIfRunning() }
            .store(in: &cancellables)
        // Keep normalizer zone bounds in sync when the user explicitly changes them
        // (comfort-zone sliders, calibrate button, or live defaults write).
        // This is intentionally separate from the volume-range subscriber below so that
        // a min/max adjustment does NOT overwrite a device-specific calibrated zone.
        settings.$targetRMSLow
            .combineLatest(settings.$targetRMSHigh)
            .dropFirst()
            .sink { [weak self] low, high in
                guard let self else { return }
                normalizer.targetRMSLow = low
                normalizer.targetRMSHigh = high
                activeTargetRMSLow = low
                activeTargetRMSHigh = high
                log.info("Zone bounds updated: targetRMSLow=\(low) high=\(high)")
            }
            .store(in: &cancellables)
        // Keep the normalizer's volume range in sync independently of the zone bounds.
        settings.$minVolume
            .combineLatest(settings.$maxVolume)
            .dropFirst()
            .sink { [weak self] minVolume, maxVolume in
                guard let self else { return }
                normalizer.minVolumeScalar = minVolume
                normalizer.maxVolumeScalar = maxVolume
                log.info("Volume range updated: min=\(minVolume) max=\(maxVolume)")
            }
            .store(in: &cancellables)
        settings.$smoothing
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                normalizer.attackSeconds = self.settings.attackSeconds
                normalizer.releaseSeconds = self.settings.releaseSeconds
                log.info(
                    "Smoothing updated: attack=\(self.settings.attackSeconds)s release=\(self.settings.releaseSeconds)s"
                )
            }
            .store(in: &cancellables)
        settings.$strength
            .dropFirst()
            .sink { [weak self] strength in
                guard let self else { return }
                normalizer.strength = strength
            }
            .store(in: &cancellables)
        // React to live isEnabled changes (e.g. via `defaults write`).
        // Note: rebuildTapIfRunning() also sets settings.isEnabled = false on failure,
        // which fires this subscriber — the guard conditions below make it a safe no-op.
        settings.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled && !isRunning {
                    start()
                    if !isRunning {
                        // start() failed; revert so persistence and UI stay consistent.
                        settings.isEnabled = false
                    }
                } else if !enabled && isRunning {
                    stop()
                }
            }
            .store(in: &cancellables)
        // Auto-start if the coordinator was enabled when the app was last quit.
        // $isEnabled uses dropFirst() and won't fire for the already-loaded value.
        if settings.isEnabled {
            start()
            if !isRunning {
                settings.isEnabled = false  // persist the corrected state
            }
        }
    }

    func start() {
        guard !isRunning else { return }  // idempotent: prevent double-start
        guard #available(macOS 14.2, *) else {
            log.error(
                "start: requires macOS 14.2+, running \(ProcessInfo.processInfo.operatingSystemVersionString)"
            )
            errorMessage = "Smart Volume requires macOS 14.2 or later."
            return
        }
        let deviceID = deviceManager.getDefaultOutputDevice()
        guard deviceID != 0, let uid = deviceManager.getDeviceUID(deviceID) else {
            log.error(
                "start: could not read default output device (id=\(self.deviceManager.getDefaultOutputDevice()))"
            )
            errorMessage = "Could not read the current output device."
            return
        }

        normalizer.maxVolumeScalar = settings.maxVolume
        normalizer.minVolumeScalar = settings.minVolume
        // Use per-device calibration when available; fall back to global settings.
        let cal = settings.calibration(forDeviceUID: uid)
        normalizer.targetRMSLow = cal?.targetRMSLow ?? settings.targetRMSLow
        normalizer.targetRMSHigh = cal?.targetRMSHigh ?? settings.targetRMSHigh
        activeTargetRMSLow = normalizer.targetRMSLow
        activeTargetRMSHigh = normalizer.targetRMSHigh
        if let cal {
            log.info(
                "start: loaded device calibration for \(uid): low=\(cal.targetRMSLow) high=\(cal.targetRMSHigh)"
            )
        }
        normalizer.attackSeconds = settings.attackSeconds
        normalizer.releaseSeconds = settings.releaseSeconds
        normalizer.strength = settings.strength
        // Seed the IIR from the current volume so the first AGC step is a smooth nudge,
        // not a sudden jump to the computed target.
        normalizer.resetWith(currentVolume: Float(volumeMonitor.volumeScalar))
        currentDeviceUID = uid

        let monitor = AudioTapMonitor()
        do {
            try monitor.start(outputDeviceUID: uid)
        } catch {
            log.error("start: AudioTapMonitor.start failed — \(error)")
            errorMessage =
                "Could not start audio monitoring (\(error)). "
                + "Please allow Volume Grid to access audio in System Settings."
            return
        }
        tapMonitor = monitor
        errorMessage = nil
        isRunning = true
        log.info(
            "start: targetRMSLow=\(self.settings.targetRMSLow) high=\(self.settings.targetRMSHigh) min=\(self.settings.minVolume) max=\(self.settings.maxVolume) device=\(uid)"
        )

        // Start SoundAnalysis scene classifier.
        // Failures are non-fatal: Smart Volume continues without scene detection.
        let classif = SoundSceneClassifier()
        do {
            try classif.setup(
                sampleRate: Double(monitor.tapSampleRate), channelCount: 1)
            classifier = classif
            // No dropFirst: receive the initial .ambient so currentScene is never nil
            // while Smart Volume is running.
            classif.$currentScene
                .sink { [weak self] scene in
                    self?.applySceneProfile(scene)
                }
                .store(in: &classifierCancellables)
            classif.$speechConfidence
                .sink { [weak self] v in self?.speechConfidence = v }
                .store(in: &classifierCancellables)
            classif.$musicConfidence
                .sink { [weak self] v in self?.musicConfidence = v }
                .store(in: &classifierCancellables)
        } catch {
            log.error("start: SoundSceneClassifier setup failed: \(error)")
        }

        // Volume key presses adjust the active Grid Range ceiling while Smart Volume is on.
        volumeMonitor.keyPressPublisher
            .sink { [weak self] key in self?.handleVolumeKey(key) }
            .store(in: &classifierCancellables)

        let interval = Double(timerInterval)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self, weak monitor, weak classif] in
            guard let self, let monitor else { return }
            // nil = no fresh data since last poll; skip this AGC cycle
            guard let (rms, _) = monitor.drainMetrics() else { return }
            let dt = self.timerInterval
            // Drain classification samples and pass raw [Float32] + sample rate to
            // the classifier.  [Float32] is a value type (Sendable) so it crosses
            // thread boundaries safely without any special wrapper.
            // Weak capture avoids a data race: stop() on @MainActor may nil _classifierBox
            // concurrently; weak var access is ARC-atomic and nonisolated analyze() is safe
            // to call from any thread.
            if let samples = monitor.drainClassificationSamples() {
                let sr = Double(monitor.tapSampleRate)
                classif?.analyze(samples: samples, sampleRate: sr)
            }
            Task { @MainActor [weak self] in
                self?.handleAGC(rms: rms, dt: dt)
            }
        }
        timer.resume()
        smartVolumeTimer = timer
    }

    func stop() {
        smartVolumeTimer?.cancel()
        smartVolumeTimer = nil
        if #available(macOS 14.2, *) {
            tapMonitor?.stop()
            tapMonitor = nil
        }
        if #available(macOS 14.2, *) {
            classifier?.reset()
            classifier = nil
        }
        classifierCancellables.removeAll()
        normalizer.reset()
        smoothedRMS = 0.0
        diagHoldTicks = 0
        pendingVolumeTask?.cancel()
        pendingVolumeTask = nil
        pendingVolumeBase = nil
        isRunning = false
        lastMeasuredRMS = nil
        currentScene = nil
        speechConfidence = 0
        musicConfidence = 0
        currentDeviceUID = nil
        // Reset active zone to reflect global settings (no device running).
        activeTargetRMSLow = settings.targetRMSLow
        activeTargetRMSHigh = settings.targetRMSHigh
    }

    /// Recentre the dead zone around the current perceived loudness (±6 dB margins).
    /// No-op if the tap is not running or no audio has been measured yet.
    func calibrateTargetRMS() {
        guard isRunning, smoothedRMS > 1e-5 else { return }
        let perceived = smoothedRMS * Float(volumeMonitor.volumeScalar)
        let newLow = max(0.01, perceived * 0.5)
        let newHigh = min(0.30, perceived * 2.0)
        settings.targetRMSLow = newLow
        settings.targetRMSHigh = newHigh
        normalizer.targetRMSLow = newLow
        normalizer.targetRMSHigh = newHigh
        if let uid = currentDeviceUID {
            settings.saveCalibration(
                SmartVolumeSettings.DeviceCalibration(targetRMSLow: newLow, targetRMSHigh: newHigh),
                forDeviceUID: uid
            )
        }
        log.info(
            "calibrateTargetRMS: perceived=\(perceived) → zone=[\(newLow), \(newHigh)]")
    }

    // MARK: - Volume key handling

    private func handleVolumeKey(_ key: VolumeKey) {
        guard isRunning else {
            log.debug("volumeKey dropped: Smart Volume not running")
            return
        }
        switch key {
        case .up:
            // Ignore volume keys while muted: volumeScalar is 0 during mute, which would
            // drive AGC calibration from a meaningless base.  macOS handles the unmute +
            // volume change itself; the AGC reseeds on the unmute edge in handleAGC().
            guard !volumeMonitor.isMuted else { return }
            adjustVolume(up: true)
        case .down:
            guard !volumeMonitor.isMuted else { return }
            adjustVolume(up: false)
        case .mute:
            // Mute is handled by VolumeMonitor's HUD path; no AGC action needed.
            break
        }
    }

    /// Shift the active Grid Range ceiling or recentre the AGC dead zone by one grid step.
    ///
    /// At ceiling (current ≈ activeMax):
    ///   - up: raise ceiling (user needs more headroom)
    ///   - down: lower ceiling (user thinks the ceiling is too high)
    ///
    /// Mid-range (current well below ceiling):
    ///   - Ceiling stays; recentre the dead zone so the AGC holds the new level.
    private func adjustVolume(up: Bool) {
        let activeMax = settings.maxVolume
        // Use pendingVolumeBase while CoreAudio hasn't yet reflected the last key press
        // (~50 ms lag), so rapid successive presses accumulate correctly.
        let current = pendingVolumeBase ?? Float(volumeMonitor.volumeScalar)
        let effect = VolumeKeyEffect.compute(
            up: up, currentVolume: current, activeMax: activeMax,
            minVolume: settings.minVolume)

        // Remember where the user is heading; cleared once CoreAudio settles (~200 ms).
        pendingVolumeBase = effect.seedVolume
        pendingVolumeTask?.cancel()
        // `try?` discards the CancellationError from Task.sleep; `guard !isCancelled`
        // then exits early so a cancelled (superseded) task never clears pendingVolumeBase.
        pendingVolumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingVolumeBase = nil
        }

        if let newMax = effect.newMax {
            settings.maxVolume = newMax
            normalizer.maxVolumeScalar = newMax
            log.info(
                "volumeKey \(up ? "up" : "down") at ceiling: vol=\(current) newMax=\(newMax)"
            )
        } else {
            log.info(
                "volumeKey \(up ? "up" : "down") mid-range: vol=\(current) activeMax=\(activeMax) smoothedRMS=\(self.smoothedRMS) seed=\(effect.seedVolume)"
            )
            if smoothedRMS > 1e-5 {
                let newCenter = smoothedRMS * effect.seedVolume
                let newLow = max(0.01, newCenter * 0.5)
                let newHigh = min(0.30, newCenter * 2.0)
                settings.targetRMSLow = newLow
                settings.targetRMSHigh = newHigh
                normalizer.targetRMSLow = newLow
                normalizer.targetRMSHigh = newHigh
            }
        }
        // Reseed normalizer so the system volume settles at the intended level immediately.
        normalizer.resetWith(currentVolume: effect.seedVolume)
    }

    func rebuildTapIfRunning() {
        guard isRunning else { return }
        stop()
        start()
        // If restart failed (e.g. new device has no tap support), keep isEnabled consistent.
        if !isRunning {
            let reason = errorMessage ?? "unknown error"
            log.error("rebuildTapIfRunning: failed to restart tap — \(reason)")
            settings.isEnabled = false
        }
    }

    // MARK: - Scene-aware profile switching

    @available(macOS 14.2, *)
    private func applySceneProfile(_ scene: SoundSceneClassifier.Scene) {
        currentScene = scene.description
        // Dead-zone model uses the same [targetRMSLow, targetRMSHigh] for all scenes.
        // Scene info is kept for display only.
        log.info("Scene → \(scene): (informational only, no zone change)")
    }

    // MARK: - AGC (Main Actor)

    private func handleAGC(rms: Float, dt: Float) {
        guard isRunning else { return }
        let muted = volumeMonitor.isMuted
        // On the mute edge, clear diagnostics immediately so the menu and calibrate button
        // reflect the absence of audible output rather than retaining the pre-mute RMS.
        if !wasMuted && muted {
            diagHoldTicks = 0
            lastMeasuredRMS = nil
        }
        // On the unmute edge, reseed the normalizer from the user-chosen volume.
        // Without this, the IIR would immediately pull the volume back to where it
        // was before the mute, ignoring whatever the user set while muted.
        if wasMuted && !muted {
            normalizer.resetWith(currentVolume: Float(volumeMonitor.volumeScalar))
            smoothedRMS = 0.0  // discard stale smoothed level from before mute
        }
        wasMuted = muted
        guard !muted else { return }
        // Asymmetric RMS pre-smoothing: rising level is tracked quickly so loud content
        // is caught fast; falling level is tracked slowly so pauses don't look like silence.
        let rmsAlpha =
            rms > smoothedRMS
            ? 1 - expf(-timerInterval / rmsRisingSeconds)  // fast: track rising loudness
            : 1 - expf(-timerInterval / rmsFallingSeconds)  // slow: hold during quiet spans
        smoothedRMS = rmsAlpha * rms + (1 - rmsAlpha) * smoothedRMS
        let currentVol = Float(volumeMonitor.volumeScalar)
        // Update diagnostics whenever audio is present, even when inside the comfort zone
        // (so the calibrate button stays active and the menu shows live RMS, not "no signal").
        // Gate check uses raw rms (current tick) so the hold counter resets only on actual
        // audio, not on the slow smoothedRMS tail. The hold absorbs brief speech pauses
        // (≤ 600 ms) without flickering the display to nil.
        let noiseGate = max(1e-5, normalizer.targetRMSLow * 0.2)
        if rms > noiseGate {
            diagHoldTicks = diagHoldThreshold
            lastMeasuredRMS = smoothedRMS
        } else if diagHoldTicks > 0 {
            diagHoldTicks -= 1
            lastMeasuredRMS = smoothedRMS  // hold window: keep display stable
        } else {
            lastMeasuredRMS = nil  // hold expired — genuine silence
        }
        if let newVolume = normalizer.update(
            measuredRMS: smoothedRMS, currentVolume: currentVol, dt: dt)
        {
            log.debug(
                "AGC measuredRMS=\(rms) curVol=\(Float(self.volumeMonitor.volumeScalar)) → \(newVolume)"
            )
            // Smart Volume writes volume exactly like a user action — HUD shows normally.
            volumeMonitor.setVolume(scalar: newVolume)
        }
    }
}
