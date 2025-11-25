import XCTest

@testable import Volume_Grid

/// Additional comprehensive tests for VolumeFormatter volume conversion logic
final class VolumeFormatterExtendedTests: XCTestCase {

    // MARK: - Scalar to Percentage Conversion

    func testFormattedVolumeStringScalarEdgeCases() {
        let nearZero = VolumeFormatter.formattedVolumeString(forScalar: 0.0001)
        XCTAssertEqual(nearZero, "0")

        let nearMax = VolumeFormatter.formattedVolumeString(forScalar: 0.9999)
        XCTAssertEqual(nearMax, "16")
    }

    func testFormattedVolumeStringScalarQuarterValues() {
        let quarter = VolumeFormatter.formattedVolumeString(forScalar: 0.25)
        XCTAssertEqual(quarter, "4")

        let threeQuarters = VolumeFormatter.formattedVolumeString(forScalar: 0.75)
        XCTAssertEqual(threeQuarters, "12")
    }

    // MARK: - Percentage to Block Conversion

    func testFormattedVolumeStringPercentageEdgeCases() {
        let zero = VolumeFormatter.formattedVolumeString(for: 0)
        XCTAssertEqual(zero, "0")

        let max = VolumeFormatter.formattedVolumeString(for: 100)
        XCTAssertEqual(max, "16")
    }

    func testFormattedVolumeStringPercentageQuarterPoints() {
        let p25 = VolumeFormatter.formattedVolumeString(for: 25)
        XCTAssertEqual(p25, "4")

        let p50 = VolumeFormatter.formattedVolumeString(for: 50)
        XCTAssertEqual(p50, "8")

        let p75 = VolumeFormatter.formattedVolumeString(for: 75)
        XCTAssertEqual(p75, "12")
    }

    // MARK: - Quarter Block Formatting

    func testFormatVolumeCountAllQuarterSteps() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.0), "0")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.25), "1/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.5), "2/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.75), "3/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 1.0), "1")
    }

    func testFormatVolumeCountCombinations() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 1.25), "1+1/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 4.5), "4+2/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.75), "8+3/4")
    }

    func testFormatVolumeCountMaxValue() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 16.0), "16")
    }

    func testFormatVolumeCountEpsilonHandling() {
        // Values very close to integer (within epsilon 0.001)
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 7.9995), "8")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.0005), "8")

        // Values close to quarter step
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.2499), "1/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.2501), "1/4")
    }

    // MARK: - Consistency Tests

    func testFormattedVolumeStringScalarAndPercentageConsistency() {
        let percent50 = VolumeFormatter.formattedVolumeString(for: 50)
        let scalar05 = VolumeFormatter.formattedVolumeString(forScalar: 0.5)
        XCTAssertEqual(percent50, scalar05)

        let percent100 = VolumeFormatter.formattedVolumeString(for: 100)
        let scalar10 = VolumeFormatter.formattedVolumeString(forScalar: 1.0)
        XCTAssertEqual(percent100, scalar10)
    }

    // MARK: - Boundary Tests

    func testVolumeFormatterBoundaries() {
        let negative = VolumeFormatter.formattedVolumeString(for: -50)
        XCTAssertEqual(negative, "0")

        let over100 = VolumeFormatter.formattedVolumeString(for: 150)
        XCTAssertEqual(over100, "16")
    }
}
