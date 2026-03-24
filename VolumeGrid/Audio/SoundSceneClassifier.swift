import AVFoundation
import Combine
import Foundation
import SoundAnalysis
import os.log

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
                let observer = ClassificationObserver { [weak self] speech, music in
                    Task { @MainActor [weak self] in
                        self?.applyConfidences(speech: speech, music: music)
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
    func reset() {
        analysisQueue.sync {
            if let req = observedRequest { streamAnalyzer?.remove(req) }
            streamAnalyzer = nil
            observedRequest = nil
            resultObserver = nil
            framePosition = 0
        }
        currentScene = .ambient
        speechConfidence = 0
        musicConfidence = 0
    }

    // MARK: - Private

    private func applyConfidences(speech: Double, music: Double) {
        speechConfidence = speech
        musicConfidence = music
        log.debug(
            "confidences: speech=\(String(format: "%.2f", speech)) music=\(String(format: "%.2f", music))"
        )
        let newScene: Scene
        if speech > 0.5 {
            newScene = .speech
        } else if music > 0.5 {
            newScene = .music
        } else {
            newScene = .ambient
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
    private let handler: @Sendable (_ speech: Double, _ music: Double) -> Void
    private let log = Logger(subsystem: "one.eux.volumegrid", category: "SoundScene")

    init(handler: @escaping @Sendable (_ speech: Double, _ music: Double) -> Void) {
        self.handler = handler
    }

    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let speech = result.classification(forIdentifier: "speech")?.confidence ?? 0
        let music = result.classification(forIdentifier: "music")?.confidence ?? 0
        handler(speech, music)
    }

    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        log.error("observer: classification failed: \(error)")
    }
}
