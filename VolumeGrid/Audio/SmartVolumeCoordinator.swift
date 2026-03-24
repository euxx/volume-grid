import AVFoundation
import Combine
import Dispatch
import Foundation
import os.log

/// Coordinates AudioTapMonitor, LoudnessNormalizer, and VolumeMonitor to implement
/// dynamic loudness normalisation.  Runs entirely on @MainActor except for the
/// DispatchSourceTimer fire handler (nonisolated timerQueue).
@MainActor
final class SmartVolumeCoordinator: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    /// Live diagnostics — updated every AGC tick (nil when stopped or silent).
    @Published private(set) var lastMeasuredRMS: Float?
    @Published private(set) var lastRawTarget: Float?
    /// Currently detected audio scene; nil when Smart Volume is not running or macOS < 14.2.
    @Published private(set) var currentScene: String?
    /// Live confidence scores from SoundAnalysis; 0 when classifier is inactive.
    @Published private(set) var speechConfidence: Double = 0
    @Published private(set) var musicConfidence: Double = 0

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

    private let log = Logger(subsystem: "one.eux.volumegrid", category: "SmartVolume")

    init(volumeMonitor: VolumeMonitor) {
        self.volumeMonitor = volumeMonitor
        // Rebuild the tap whenever the default output device changes.
        volumeMonitor.$currentDevice
            .dropFirst()
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] _ in self?.rebuildTapIfRunning() }
            .store(in: &cancellables)
        // Keep normalizer in sync whenever settings change while running
        // (e.g. after `defaults write` triggers a live reload).
        settings.$targetRMS
            .combineLatest(settings.$minVolume, settings.$maxVolume)
            .dropFirst()
            .sink { [weak self] targetRMS, minVolume, maxVolume in
                guard let self else { return }
                normalizer.targetRMS = targetRMS
                normalizer.minVolumeScalar = minVolume
                normalizer.maxVolumeScalar = maxVolume
                log.info(
                    "Settings updated: targetRMS=\(targetRMS) min=\(minVolume) max=\(maxVolume)")
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
        normalizer.targetRMS = settings.targetRMS
        normalizer.attackSeconds = settings.attackSeconds
        normalizer.releaseSeconds = settings.releaseSeconds
        normalizer.strength = settings.strength
        // Seed the IIR from the current volume so the first AGC step is a smooth nudge,
        // not a sudden jump to the computed target.
        normalizer.resetWith(currentVolume: Float(volumeMonitor.volumeScalar))

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
            "start: targetRMS=\(self.settings.targetRMS) min=\(self.settings.minVolume) max=\(self.settings.maxVolume) device=\(uid)"
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

        let interval = Double(timerInterval)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self, weak monitor] in
            guard let self, let monitor else { return }
            // nil = no fresh data since last poll; skip this AGC cycle
            guard let (rms, _) = monitor.drainMetrics() else { return }
            let dt = self.timerInterval
            // Drain classification samples and pass raw [Float32] + sample rate to
            // the classifier.  [Float32] is a value type (Sendable) so it crosses
            // thread boundaries safely without any special wrapper.
            if let samples = monitor.drainClassificationSamples() {
                let sr = Double(monitor.tapSampleRate)
                self.classifier?.analyze(samples: samples, sampleRate: sr)
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
        isRunning = false
        lastMeasuredRMS = nil
        lastRawTarget = nil
        currentScene = nil
        speechConfidence = 0
        musicConfidence = 0
    }

    /// Set targetRMS to the current perceived loudness so the AGC maintains
    /// the volume level the user currently considers comfortable.
    /// No-op if the tap is not running or no audio has been measured yet.
    func calibrateTargetRMS() {
        // Use smoothedRMS (what the normalizer actually acts on) for stable calibration.
        guard isRunning, smoothedRMS > 1e-5 else { return }
        let perceived = smoothedRMS * Float(volumeMonitor.volumeScalar)
        settings.targetRMS = max(0.01, min(0.30, perceived))
        log.info(
            "calibrateTargetRMS: smoothedRMS=\(self.smoothedRMS) vol=\(Float(self.volumeMonitor.volumeScalar)) → targetRMS=\(self.settings.targetRMS)"
        )
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
        switch scene {
        case .speech:
            normalizer.targetRMS = settings.speechTargetRMS
            normalizer.maxVolumeScalar = settings.speechMaxVolume
            log.info(
                "Scene → speech: targetRMS=\(self.settings.speechTargetRMS) maxVol=\(self.settings.speechMaxVolume)"
            )
        case .music, .ambient:
            normalizer.targetRMS = settings.targetRMS
            normalizer.maxVolumeScalar = settings.maxVolume
            log.info(
                "Scene → \(scene): targetRMS=\(self.settings.targetRMS) maxVol=\(self.settings.maxVolume)"
            )
        }
    }

    // MARK: - AGC (Main Actor)

    private func handleAGC(rms: Float, dt: Float) {
        guard isRunning else { return }
        let muted = volumeMonitor.isMuted
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
        let rawTarget = normalizer.targetRMS / smoothedRMS
        guard let newVolume = normalizer.update(measuredRMS: smoothedRMS, dt: dt) else { return }
        lastMeasuredRMS = rms
        lastRawTarget = rawTarget
        log.debug(
            "AGC measuredRMS=\(rms) rawTarget=\(rawTarget) curVol=\(Float(self.volumeMonitor.volumeScalar)) → \(newVolume)"
        )
        // Smart Volume writes volume exactly like a user action — HUD shows normally.
        volumeMonitor.setVolume(scalar: newVolume)
    }
}
