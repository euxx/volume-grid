import XCTest

@testable import Volume_Grid

/// Tests for VolumeGridConstants to ensure configuration values are correct
final class ConstantsTests: XCTestCase {

    // MARK: - Audio Constants

    func testAudioVolumeEpsilonValue() {
        XCTAssertEqual(VolumeGridConstants.Audio.volumeEpsilon, 0.001)
    }

    func testAudioQuarterStepValue() {
        XCTAssertEqual(VolumeGridConstants.Audio.quarterStep, 0.25)
    }

    func testAudioBlocksCountValue() {
        XCTAssertEqual(VolumeGridConstants.Audio.blocksCount, 16.0)
    }

    func testAudioVolumeChangeDebounceDelay() {
        XCTAssertEqual(VolumeGridConstants.Audio.volumeChangeDebounceDelay, 0.05)
    }

    func testAudioDeviceChangeDebounceDelay() {
        XCTAssertEqual(VolumeGridConstants.Audio.deviceChangeDebounceDelay, 0.1)
    }

    func testAudioVolumeLevelThresholds() {
        XCTAssertEqual(VolumeGridConstants.Audio.volumeLevelLow, 33)
        XCTAssertEqual(VolumeGridConstants.Audio.volumeLevelMedium, 66)
    }

    // MARK: - HUD Constants

    func testHUDDimensions() {
        XCTAssertEqual(VolumeGridConstants.HUD.width, 240)
        XCTAssertEqual(VolumeGridConstants.HUD.height, 160)
        XCTAssertEqual(VolumeGridConstants.HUD.cornerRadius, 20)
    }

    func testHUDAlpha() {
        XCTAssertEqual(VolumeGridConstants.HUD.alpha, 0.97)
        XCTAssert(VolumeGridConstants.HUD.alpha > 0 && VolumeGridConstants.HUD.alpha <= 1.0)
    }

    func testHUDDisplayDuration() {
        XCTAssertEqual(VolumeGridConstants.HUD.displayDuration, 1.4)
    }

    func testHUDAnimationDurations() {
        XCTAssertEqual(VolumeGridConstants.HUD.fadeInDuration, 0.3)
        XCTAssertEqual(VolumeGridConstants.HUD.fadeOutDuration, 0.6)
        XCTAssert(VolumeGridConstants.HUD.fadeOutDuration > VolumeGridConstants.HUD.fadeInDuration)
    }

    func testHUDMargins() {
        XCTAssertEqual(VolumeGridConstants.HUD.marginX, 10)
        XCTAssertEqual(VolumeGridConstants.HUD.minVerticalPadding, 14)
    }

    // MARK: - HUD Layout Constants

    func testHUDLayoutIconSize() {
        XCTAssertEqual(VolumeGridConstants.HUD.Layout.iconSize, 40)
    }

    func testHUDLayoutSpacing() {
        XCTAssertEqual(VolumeGridConstants.HUD.Layout.spacingIconToDevice, 16)
        XCTAssertEqual(VolumeGridConstants.HUD.Layout.spacingDeviceToBlocks, 24)
    }

    func testHUDLayoutPadding() {
        XCTAssertEqual(VolumeGridConstants.HUD.Layout.leadingSpacerWidth, 30)
        XCTAssertEqual(VolumeGridConstants.HUD.Layout.volumeLabelWidthPadding, 6)
    }

    // MARK: - Volume Blocks View Constants

    func testVolumeBlocksViewConfiguration() {
        XCTAssertEqual(VolumeGridConstants.HUD.VolumeBlocksView.blockCount, 16)
        XCTAssertEqual(VolumeGridConstants.HUD.VolumeBlocksView.blockHeight, 6)
        XCTAssertEqual(VolumeGridConstants.HUD.VolumeBlocksView.cornerRadius, 0.5)
    }

    // MARK: - Consistency Tests

    func testConstantsConsistency() {
        // Volume formatter should use same quarterStep as Constants
        XCTAssertEqual(VolumeFormatter.quarterStep, VolumeGridConstants.Audio.quarterStep)
    }

    func testHUDConstantsConsistency() {
        // Verify HUD width and height are positive
        XCTAssert(VolumeGridConstants.HUD.width > 0)
        XCTAssert(VolumeGridConstants.HUD.height > 0)

        // Display duration should be longer than fade out
        XCTAssert(VolumeGridConstants.HUD.displayDuration > VolumeGridConstants.HUD.fadeOutDuration)
    }

    func testAudioConstantsRanges() {
        // Volume epsilon should be small
        XCTAssert(VolumeGridConstants.Audio.volumeEpsilon < 0.01)

        // Quarter step should be valid volume fraction
        XCTAssert(VolumeGridConstants.Audio.quarterStep > 0)
        XCTAssert(VolumeGridConstants.Audio.quarterStep < 1.0)

        // Debounce delays should be reasonable
        XCTAssert(VolumeGridConstants.Audio.volumeChangeDebounceDelay > 0.01)
        XCTAssert(VolumeGridConstants.Audio.volumeChangeDebounceDelay < 0.2)
    }
}
