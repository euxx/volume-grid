import XCTest

@testable import VolumeGrid

@available(macOS 14.2, *)
@MainActor
final class SoundSceneHysteresisTests: XCTestCase {

    typealias Scene = SoundSceneClassifier.Scene

    // MARK: - From ambient

    func testAmbientStaysAmbientWhenConfidencesLow() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.3, music: 0.3)
        XCTAssertEqual(scene, .ambient)
    }

    func testAmbientToSpeechAtEnterThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.6, music: 0.3)
        XCTAssertEqual(scene, .speech)
    }

    func testAmbientToMusicAtEnterThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.3, music: 0.6)
        XCTAssertEqual(scene, .music)
    }

    func testAmbientStaysWhenSpeechJustBelowEnter() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.59, music: 0.3)
        XCTAssertEqual(scene, .ambient)
    }

    func testAmbientSpeechTakesPriorityOverMusic() {
        // Both above enter threshold — speech is checked first
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.7, music: 0.7)
        XCTAssertEqual(scene, .speech)
    }

    // MARK: - From speech

    func testSpeechStaysAboveExitThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .speech, speech: 0.4, music: 0.3)
        XCTAssertEqual(scene, .speech)
    }

    func testSpeechExitsToAmbientBelowExitThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .speech, speech: 0.39, music: 0.3)
        XCTAssertEqual(scene, .ambient)
    }

    func testSpeechSwitchesToMusicWhenMusicHighAndSpeechLow() {
        let scene = SoundSceneClassifier.nextScene(
            current: .speech, speech: 0.35, music: 0.7)
        XCTAssertEqual(scene, .music)
    }

    func testSpeechStaysWhenSpeechAboveExitEvenWithHighMusic() {
        // Speech >= exit threshold → stays in speech, even if music is high
        let scene = SoundSceneClassifier.nextScene(
            current: .speech, speech: 0.45, music: 0.8)
        XCTAssertEqual(scene, .speech)
    }

    // MARK: - From music

    func testMusicStaysAboveExitThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .music, speech: 0.3, music: 0.4)
        XCTAssertEqual(scene, .music)
    }

    func testMusicExitsToAmbientBelowExitThreshold() {
        let scene = SoundSceneClassifier.nextScene(
            current: .music, speech: 0.3, music: 0.39)
        XCTAssertEqual(scene, .ambient)
    }

    func testMusicSwitchesToSpeechWhenSpeechHighAndMusicLow() {
        let scene = SoundSceneClassifier.nextScene(
            current: .music, speech: 0.7, music: 0.35)
        XCTAssertEqual(scene, .speech)
    }

    func testMusicStaysWhenMusicAboveExitEvenWithHighSpeech() {
        let scene = SoundSceneClassifier.nextScene(
            current: .music, speech: 0.8, music: 0.45)
        XCTAssertEqual(scene, .music)
    }

    // MARK: - Hysteresis prevents flicker

    func testHysteresisGapPreventsFlicker() {
        // In speech at 0.5 confidence: above exit (0.4) but below enter (0.6)
        // Simulates a user in a noisy environment where speech confidence oscillates
        var scene: Scene = .ambient

        // Enter speech (confidence rises to 0.65)
        scene = SoundSceneClassifier.nextScene(current: scene, speech: 0.65, music: 0.1)
        XCTAssertEqual(scene, .speech)

        // Confidence drops to 0.45 — still above exit threshold
        scene = SoundSceneClassifier.nextScene(current: scene, speech: 0.45, music: 0.1)
        XCTAssertEqual(scene, .speech, "Should stay in speech (above exit threshold)")

        // Confidence drops to 0.55 — still above exit threshold
        scene = SoundSceneClassifier.nextScene(current: scene, speech: 0.55, music: 0.1)
        XCTAssertEqual(scene, .speech, "Should stay in speech")

        // Confidence drops below exit threshold
        scene = SoundSceneClassifier.nextScene(current: scene, speech: 0.35, music: 0.1)
        XCTAssertEqual(scene, .ambient, "Should exit speech")

        // Confidence bounces back to hysteresis gap (above exit, below enter)
        scene = SoundSceneClassifier.nextScene(current: scene, speech: 0.55, music: 0.1)
        XCTAssertEqual(scene, .ambient, "Should NOT re-enter speech (below enter threshold)")
    }

    // MARK: - Boundary values

    func testExactEnterThresholdEntersScene() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.6, music: 0.0)
        XCTAssertEqual(scene, .speech)
    }

    func testExactExitThresholdStaysInScene() {
        let scene = SoundSceneClassifier.nextScene(
            current: .speech, speech: 0.4, music: 0.0)
        XCTAssertEqual(scene, .speech)
    }

    func testZeroConfidencesStayAmbient() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 0.0, music: 0.0)
        XCTAssertEqual(scene, .ambient)
    }

    func testMaxConfidenceEntersScene() {
        let scene = SoundSceneClassifier.nextScene(
            current: .ambient, speech: 1.0, music: 0.0)
        XCTAssertEqual(scene, .speech)
    }
}
