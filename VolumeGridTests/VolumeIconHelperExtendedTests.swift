import XCTest

@testable import Volume_Grid

/// Additional tests for VolumeIconHelper icon selection logic
final class VolumeIconHelperExtendedTests: XCTestCase {

    // MARK: - Icon Selection Logic (Regular)

    func testIconSelectionAcrossRange() {
        let icon0 = VolumeIconHelper.icon(for: 0)
        XCTAssertEqual(icon0.symbolName, "speaker.slash")

        let icon20 = VolumeIconHelper.icon(for: 20)
        XCTAssertEqual(icon20.symbolName, "speaker.wave.1")

        let icon50 = VolumeIconHelper.icon(for: 50)
        XCTAssertEqual(icon50.symbolName, "speaker.wave.2")

        let icon80 = VolumeIconHelper.icon(for: 80)
        XCTAssertEqual(icon80.symbolName, "speaker.wave.3")
    }

    func testIconSelectionBoundaries() {
        XCTAssertEqual(VolumeIconHelper.icon(for: 32).symbolName, "speaker.wave.1")
        XCTAssertEqual(VolumeIconHelper.icon(for: 33).symbolName, "speaker.wave.2")

        XCTAssertEqual(VolumeIconHelper.icon(for: 65).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: 66).symbolName, "speaker.wave.3")
    }

    // MARK: - Icon Sizes (Regular)

    func testIconSizesMuted() {
        let icon = VolumeIconHelper.icon(for: 0)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeStatusBar)
    }

    func testIconSizesLow() {
        let icon = VolumeIconHelper.icon(for: 20)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeLow)
    }

    func testIconSizesMedium() {
        let icon = VolumeIconHelper.icon(for: 50)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeMedium)
    }

    func testIconSizesHigh() {
        let icon = VolumeIconHelper.icon(for: 80)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeHigh)
    }

    // MARK: - Unsupported Device Icons

    func testIconUnsupportedDevice() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertEqual(icon.symbolName, "nosign")
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeUnsupported)
    }

    func testIconUnsupportedIgnoresVolume() {
        for volume in [0, 25, 50, 75, 100] {
            let icon = VolumeIconHelper.icon(for: volume, isUnsupported: true)
            XCTAssertEqual(icon.symbolName, "nosign")
        }
    }

    // MARK: - HUD Icon Selection

    func testHUDIconSelectionAcrossRange() {
        let icon0 = VolumeIconHelper.hudIcon(for: 0)
        XCTAssertEqual(icon0.symbolName, "speaker.slash.fill")

        let icon20 = VolumeIconHelper.hudIcon(for: 20)
        XCTAssertEqual(icon20.symbolName, "speaker.wave.1.fill")

        let icon50 = VolumeIconHelper.hudIcon(for: 50)
        XCTAssertEqual(icon50.symbolName, "speaker.wave.2.fill")

        let icon80 = VolumeIconHelper.hudIcon(for: 80)
        XCTAssertEqual(icon80.symbolName, "speaker.wave.3.fill")
    }

    // MARK: - HUD Icon Sizes

    func testHUDIconSizesMuted() {
        let icon = VolumeIconHelper.hudIcon(for: 0)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeHUDMuted)
    }

    func testHUDIconSizesLow() {
        let icon = VolumeIconHelper.hudIcon(for: 20)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeHUDLow)
    }

    func testHUDIconSizesMedium() {
        let icon = VolumeIconHelper.hudIcon(for: 50)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeHUDMedium)
    }

    func testHUDIconSizesHigh() {
        let icon = VolumeIconHelper.hudIcon(for: 80)
        XCTAssertEqual(icon.size, VolumeGridConstants.HUD.Icons.sizeHUDHigh)
    }

    // MARK: - Clamping Behavior

    func testIconClampsNegativePercentage() {
        let iconNegative = VolumeIconHelper.icon(for: -50)
        let iconZero = VolumeIconHelper.icon(for: 0)
        XCTAssertEqual(iconNegative.symbolName, iconZero.symbolName)
    }

    func testIconClampsPercentageAbove100() {
        let iconOver = VolumeIconHelper.icon(for: 150)
        let iconMax = VolumeIconHelper.icon(for: 100)
        XCTAssertEqual(iconOver.symbolName, iconMax.symbolName)
    }

    func testHUDIconClampsNegativePercentage() {
        let iconNegative = VolumeIconHelper.hudIcon(for: -50)
        let iconZero = VolumeIconHelper.hudIcon(for: 0)
        XCTAssertEqual(iconNegative.symbolName, iconZero.symbolName)
    }

    func testHUDIconClampsPercentageAbove100() {
        let iconOver = VolumeIconHelper.hudIcon(for: 150)
        let iconMax = VolumeIconHelper.hudIcon(for: 100)
        XCTAssertEqual(iconOver.symbolName, iconMax.symbolName)
    }

    // MARK: - Consistency Tests

    func testRegularAndHUDIconsHaveSameLevels() {
        for volume in [0, 20, 50, 80, 100] {
            let regular = VolumeIconHelper.icon(for: volume)
            let hud = VolumeIconHelper.hudIcon(for: volume)

            let regularBase = regular.symbolName.replacingOccurrences(of: ".fill", with: "")
            let hudBase = hud.symbolName.replacingOccurrences(of: ".fill", with: "")

            XCTAssertEqual(regularBase, hudBase)
        }
    }

    func testHUDIconsSizeIsLarger() {
        for volume in [0, 20, 50, 80, 100] {
            let regular = VolumeIconHelper.icon(for: volume)
            let hud = VolumeIconHelper.hudIcon(for: volume)

            XCTAssert(hud.size > regular.size)
        }
    }

    // MARK: - Edge Cases

    func testIconWithExtremeValues() {
        let veryNegative = VolumeIconHelper.icon(for: -1000)
        XCTAssertEqual(veryNegative.symbolName, "speaker.slash")

        let veryLarge = VolumeIconHelper.icon(for: 10000)
        XCTAssertEqual(veryLarge.symbolName, "speaker.wave.3")
    }

    // MARK: - Volume Threshold Verification

    func testVolumeLevelThresholdsFromConstants() {
        let low = VolumeGridConstants.Audio.volumeLevelLow
        let medium = VolumeGridConstants.Audio.volumeLevelMedium

        XCTAssertEqual(VolumeIconHelper.icon(for: low - 1).symbolName, "speaker.wave.1")
        XCTAssertEqual(VolumeIconHelper.icon(for: low).symbolName, "speaker.wave.2")

        XCTAssertEqual(VolumeIconHelper.icon(for: medium - 1).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: medium).symbolName, "speaker.wave.3")
    }
}
