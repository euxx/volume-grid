import XCTest

@testable import Volume_Grid

final class HelpersTests: XCTestCase {

    // MARK: - Comparable.clamped(to:)

    func testClampedWithinRange() {
        XCTAssertEqual(50.clamped(to: 0...100), 50)
        XCTAssertEqual(0.5.clamped(to: 0.0...1.0), 0.5)
    }

    func testClampedBelowRange() {
        XCTAssertEqual((-10).clamped(to: 0...100), 0)
        XCTAssertEqual((-0.5).clamped(to: 0.0...1.0), 0.0)
    }

    func testClampedAboveRange() {
        XCTAssertEqual(150.clamped(to: 0...100), 100)
        XCTAssertEqual(1.5.clamped(to: 0.0...1.0), 1.0)
    }

    func testClampedAtBoundaries() {
        XCTAssertEqual(0.clamped(to: 0...100), 0)
        XCTAssertEqual(100.clamped(to: 0...100), 100)
    }

    // MARK: - VolumeFormatter.formattedVolumeString(for:)

    func testFormattedVolumeStringZero() {
        let result = VolumeFormatter.formattedVolumeString(for: 0)
        XCTAssertEqual(result, "0")
    }

    func testFormattedVolumeStringFull() {
        let result = VolumeFormatter.formattedVolumeString(for: 100)
        XCTAssertEqual(result, "16")
    }

    func testFormattedVolumeStringHalf() {
        let result = VolumeFormatter.formattedVolumeString(for: 50)
        XCTAssertEqual(result, "8")
    }

    func testFormattedVolumeStringQuarter() {
        let result = VolumeFormatter.formattedVolumeString(for: 25)
        XCTAssertEqual(result, "4")
    }

    func testFormattedVolumeStringClampsNegative() {
        let result = VolumeFormatter.formattedVolumeString(for: -10)
        XCTAssertEqual(result, "0")
    }

    func testFormattedVolumeStringClampsAbove100() {
        let result = VolumeFormatter.formattedVolumeString(for: 150)
        XCTAssertEqual(result, "16")
    }

    // MARK: - VolumeFormatter.formattedVolumeString(forScalar:)

    func testFormattedVolumeStringForScalarZero() {
        let result = VolumeFormatter.formattedVolumeString(forScalar: 0.0)
        XCTAssertEqual(result, "0")
    }

    func testFormattedVolumeStringForScalarFull() {
        let result = VolumeFormatter.formattedVolumeString(forScalar: 1.0)
        XCTAssertEqual(result, "16")
    }

    func testFormattedVolumeStringForScalarHalf() {
        let result = VolumeFormatter.formattedVolumeString(forScalar: 0.5)
        XCTAssertEqual(result, "8")
    }

    // MARK: - VolumeFormatter.formatVolumeCount(quarterBlocks:)

    func testFormatVolumeCountInteger() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.0), "8")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.0), "0")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 16.0), "16")
    }

    func testFormatVolumeCountQuarter() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.25), "1/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.25), "8+1/4")
    }

    func testFormatVolumeCountHalf() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.5), "2/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 4.5), "4+2/4")
    }

    func testFormatVolumeCountThreeQuarters() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.75), "3/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 12.75), "12+3/4")
    }

    func testFormatVolumeCountNearInteger() {
        // Values very close to integer (within epsilon) should round to integer
        // volumeEpsilon = 0.001, so 7.9995 should round to 8, but 7.999 won't
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 7.9995), "8")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.0005), "8")
    }

    // MARK: - VolumeIconHelper

    func testVolumeIconMuted() {
        let icon = VolumeIconHelper.icon(for: 0)
        XCTAssertEqual(icon.symbolName, "speaker.slash")
    }

    func testVolumeIconLow() {
        let icon = VolumeIconHelper.icon(for: 20)
        XCTAssertEqual(icon.symbolName, "speaker.wave.1")
    }

    func testVolumeIconMedium() {
        let icon = VolumeIconHelper.icon(for: 50)
        XCTAssertEqual(icon.symbolName, "speaker.wave.2")
    }

    func testVolumeIconHigh() {
        let icon = VolumeIconHelper.icon(for: 80)
        XCTAssertEqual(icon.symbolName, "speaker.wave.3")
    }

    func testVolumeIconUnsupported() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertEqual(icon.symbolName, "nosign")
    }

    func testVolumeIconForHUD() {
        let icon = VolumeIconHelper.hudIcon(for: 0)
        XCTAssertEqual(icon.symbolName, "speaker.slash.fill")

        let iconLow = VolumeIconHelper.hudIcon(for: 20)
        XCTAssertEqual(iconLow.symbolName, "speaker.wave.1.fill")

        let iconMed = VolumeIconHelper.hudIcon(for: 50)
        XCTAssertEqual(iconMed.symbolName, "speaker.wave.2.fill")

        let iconHigh = VolumeIconHelper.hudIcon(for: 80)
        XCTAssertEqual(iconHigh.symbolName, "speaker.wave.3.fill")
    }

    func testVolumeIconBoundaries() {
        // Test boundary values: 0, 32, 33, 65, 66, 100
        XCTAssertEqual(VolumeIconHelper.icon(for: 32).symbolName, "speaker.wave.1")
        XCTAssertEqual(VolumeIconHelper.icon(for: 33).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: 65).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: 66).symbolName, "speaker.wave.3")
    }

    func testVolumeIconClampsInput() {
        // Negative values should be clamped to 0
        let iconNegative = VolumeIconHelper.icon(for: -10)
        XCTAssertEqual(iconNegative.symbolName, "speaker.slash")

        // Values > 100 should be clamped to 100
        let iconOver = VolumeIconHelper.icon(for: 150)
        XCTAssertEqual(iconOver.symbolName, "speaker.wave.3")
    }
}
