import AVFoundation
import Combine
import Foundation
import SoundAnalysis
import os.log

/// Represents one sound category returned by SoundAnalysis, ranked by confidence.
/// Defined at the top level so it can be referenced from SmartVolumeCoordinator without
/// requiring an @available(macOS 14.2, *) guard on the coordinator's stored properties.
struct TopClassification: Identifiable, Sendable {
    var id: String { identifier }
    let identifier: String
    let confidence: Double
}

/// Classifies the current audio scene (speech, music, ambient) using Apple's built-in
/// SoundAnalysis classifier.  Feed mono PCM buffers via `analyze(_:)`, then observe
/// `currentScene` and confidence properties.
///
/// Requires macOS 14.2+.  Smart Volume already requires macOS 14.2 (AudioProcessTap),
/// so this constraint is always satisfied when the classifier is active.
@available(macOS 14.2, *)
@MainActor
final class SoundSceneClassifier {

    enum Scene: Equatable, CustomStringConvertible {
        case speech
        case music
        case ambient

        var description: String {
            switch self {
            case .speech: return "speech"
            case .music: return "music"
            case .ambient: return "ambient"
            }
        }
    }

    @Published private(set) var currentScene: Scene = .ambient
    @Published private(set) var speechConfidence: Double = 0
    @Published private(set) var musicConfidence: Double = 0
    @Published private(set) var silenceConfidence: Double = 0
    @Published private(set) var topClassifications: [TopClassification] = []

    // SNAudioStreamAnalyzer must be called serially from one thread.
    // We use a dedicated serial background queue; analysisQueue and streamAnalyzer
    // are nonisolated(unsafe) because they are only accessed from that queue.
    private let analysisQueue = DispatchQueue(
        label: "one.eux.volumegrid.SoundSceneClassifier", qos: .userInitiated)
    // SNAudioStreamAnalyzer does NOT retain the observer — we must hold strong references.
    private nonisolated(unsafe) var streamAnalyzer: SNAudioStreamAnalyzer?
    private nonisolated(unsafe) var observedRequest: SNRequest?
    private nonisolated(unsafe) var resultObserver: (NSObject & SNResultsObserving)?
    private nonisolated(unsafe) var framePosition: AVAudioFramePosition = 0
    private let log = Logger(subsystem: "one.eux.volumegrid", category: "SoundScene")

    var isSetup: Bool { streamAnalyzer != nil }

    /// Prepare the analyzer for audio at the given format.
    func setup(sampleRate: Double, channelCount: UInt32) throws {
        reset()
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: min(channelCount, 2)
            )
        else {
            throw SetupError.invalidFormat
        }
        // Sync on analysisQueue to set up the analyzer there so all subsequent
        // analyze() calls run on the same queue — the requirement for SNAudioStreamAnalyzer.
        var setupError: Error?
        analysisQueue.sync {
            let analyzer = SNAudioStreamAnalyzer(format: format)
            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                let observer = ClassificationObserver { [weak self] speech, music, silence, top in
                    Task { @MainActor [weak self] in
                        self?.applyConfidences(
                            speech: speech, music: music, silence: silence, top: top)
                    }
                }
                try analyzer.add(request, withObserver: observer)
                self.streamAnalyzer = analyzer
                self.observedRequest = request
                self.resultObserver = observer  // must be retained; SNAudioStreamAnalyzer does not retain it
                self.framePosition = 0
            } catch {
                setupError = error
            }
        }
        if let err = setupError { throw err }
        log.info("setup: sampleRate=\(sampleRate) channels=\(channelCount)")
    }

    /// Submit raw mono Float32 samples for classification.
    /// Runs asynchronously on the analysis queue — non-blocking from the caller's perspective.
    /// Safe to call from any thread. `[Float32]` is a value type (Sendable).
    nonisolated func analyze(samples: [Float32], sampleRate: Double) {
        analysisQueue.async {
            guard let analyzer = self.streamAnalyzer else {
                self.log.warning("analyze: no streamAnalyzer")
                return
            }
            guard
                let format = AVAudioFormat(
                    standardFormatWithSampleRate: sampleRate, channels: 1),
                let pcm = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: UInt32(samples.count))
            else {
                self.log.warning("analyze: could not create AVAudioPCMBuffer")
                return
            }
            pcm.frameLength = pcm.frameCapacity
            if let ch = pcm.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { buf in
                    ch.initialize(from: buf.baseAddress!, count: samples.count)
                }
            }
            let pos = self.framePosition
            self.framePosition += AVAudioFramePosition(pcm.frameLength)
            analyzer.analyze(pcm, atAudioFramePosition: pos)
        }
    }

    /// Stop analysis and reset all state.
    /// The analyzer teardown is enqueued asynchronously so the main thread is never
    /// blocked waiting for in-flight ML inference to finish.  Published state resets
    /// immediately.  `setup()` calls this before its own `analysisQueue.sync`, so the
    /// serial queue guarantees teardown completes before any new session is established.
    func reset() {
        analysisQueue.async {
            if let req = self.observedRequest { self.streamAnalyzer?.remove(req) }
            self.streamAnalyzer = nil
            self.observedRequest = nil
            self.resultObserver = nil
            self.framePosition = 0
        }
        currentScene = .ambient
        speechConfidence = 0
        musicConfidence = 0
        silenceConfidence = 0
        topClassifications = []
    }

    // MARK: - Private

    // Hysteresis thresholds: higher confidence required to enter a scene than to stay in it.
    // This prevents rapid scene flipping near the boundary (e.g. speech+background music),
    // which would cause audible targetRMS toggling at ~0.5 Hz.
    private static let sceneEnterThreshold = 0.6
    private static let sceneExitThreshold = 0.4

    private func applyConfidences(
        speech: Double, music: Double, silence: Double, top: [TopClassification]
    ) {
        speechConfidence = speech
        musicConfidence = music
        silenceConfidence = silence
        topClassifications = top
        log.debug(
            "confidences: speech=\(String(format: "%.2f", speech)) music=\(String(format: "%.2f", music))"
        )
        // Apply hysteresis: use different thresholds for entering vs staying in a scene.
        let newScene: Scene
        switch currentScene {
        case .speech:
            if speech >= Self.sceneExitThreshold {
                newScene = .speech
            } else if music >= Self.sceneEnterThreshold {
                newScene = .music
            } else {
                newScene = .ambient
            }
        case .music:
            if music >= Self.sceneExitThreshold {
                newScene = .music
            } else if speech >= Self.sceneEnterThreshold {
                newScene = .speech
            } else {
                newScene = .ambient
            }
        case .ambient:
            if speech >= Self.sceneEnterThreshold {
                newScene = .speech
            } else if music >= Self.sceneEnterThreshold {
                newScene = .music
            } else {
                newScene = .ambient
            }
        }
        guard newScene != currentScene else { return }
        currentScene = newScene
        log.info(
            "scene → \(newScene) (speech=\(String(format: "%.2f", speech)) music=\(String(format: "%.2f", music)))"
        )
    }

    enum SetupError: Error { case invalidFormat }
}

// MARK: - SNResultsObserving wrapper

/// Bridges SNResultsObserving (Obj-C protocol) to a Swift closure.
/// Marked nonisolated because SoundAnalysis calls it on its own internal thread.
@available(macOS 14.2, *)
private final class ClassificationObserver: NSObject, SNResultsObserving {
    private let handler:
        @Sendable (_ speech: Double, _ music: Double, _ silence: Double, _ top: [TopClassification])
            -> Void
    private let log = Logger(subsystem: "one.eux.volumegrid", category: "SoundScene")

    init(
        handler:
            @escaping @Sendable (
                _ speech: Double, _ music: Double, _ silence: Double, _ top: [TopClassification]
            ) -> Void
    ) {
        self.handler = handler
    }

    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let speech = result.classification(forIdentifier: "speech")?.confidence ?? 0
        let music = result.classification(forIdentifier: "music")?.confidence ?? 0
        let silence = result.classification(forIdentifier: "silence")?.confidence ?? 0
        // result.classifications is already sorted highest→lowest confidence
        let top = result.classifications.prefix(5).map {
            TopClassification(identifier: $0.identifier, confidence: $0.confidence)
        }
        handler(speech, music, silence, Array(top))
    }

    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        log.error("observer: classification failed: \(error)")
    }
}
