import XCTest

@testable import Volume_Grid

// MARK: - Comparable.clamped(to:) Tests

final class ComparableClampTests: XCTestCase {

    // MARK: - Parameterized Boundary Tests

    func testClampedBoundaries() {
        let intTestCases: [(value: Int, range: ClosedRange<Int>, expected: Int)] = [
            (50, 0...100, 50),
            (-10, 0...100, 0),
            (150, 0...100, 100),
            (0, 0...100, 0),
            (100, 0...100, 100),
            (Int.min, 0...100, 0),
            (Int.max, 0...100, 100),
        ]

        for testCase in intTestCases {
            XCTAssertEqual(
                testCase.value.clamped(to: testCase.range),
                testCase.expected,
                "clamped(\(testCase.value)) in \(testCase.range) should be \(testCase.expected)"
            )
        }

        let floatTestCases: [(value: CGFloat, range: ClosedRange<CGFloat>, expected: CGFloat)] = [
            (0.5, 0.0...1.0, 0.5),
            (-0.5, 0.0...1.0, 0.0),
            (1.5, 0.0...1.0, 1.0),
            (CGFloat.greatestFiniteMagnitude, 0...1, 1.0),
            (-CGFloat.greatestFiniteMagnitude, 0...1, 0.0),
        ]

        for testCase in floatTestCases {
            XCTAssertEqual(
                testCase.value.clamped(to: testCase.range),
                testCase.expected,
                "clamped(\(testCase.value)) in \(testCase.range) should be \(testCase.expected)"
            )
        }
    }
}

// MARK: - VolumeFormatter Tests

final class VolumeFormatterTests: XCTestCase {

    // MARK: - Parameterized formattedVolumeString Tests

    func testFormattedVolumeStringForPercentage() {
        let testCases: [(percentage: Int, expected: String)] = [
            (0, "0"),
            (25, "4"),
            (50, "8"),
            (75, "12"),
            (100, "16"),
        ]

        for testCase in testCases {
            XCTAssertEqual(
                VolumeFormatter.formattedVolumeString(for: testCase.percentage),
                testCase.expected,
                "formattedVolumeString(for: \(testCase.percentage)) should be \(testCase.expected)"
            )
        }
    }

    func testFormattedVolumeStringForScalar() {
        let testCases: [(scalar: CGFloat, expected: String)] = [
            (0.0, "0"),
            (0.25, "4"),
            (0.5, "8"),
            (0.75, "12"),
            (1.0, "16"),
            (0.0001, "0"),
            (0.9999, "16"),
        ]

        for testCase in testCases {
            XCTAssertEqual(
                VolumeFormatter.formattedVolumeString(forScalar: testCase.scalar),
                testCase.expected,
                "formattedVolumeString(forScalar: \(testCase.scalar)) should be \(testCase.expected)"
            )
        }
    }

    func testFormattedVolumeStringBoundaries() {
        let boundaryTestCases: [(value: Int, expected: String)] = [
            (-1000, "0"),
            (-100, "0"),
            (-50, "0"),
            (-1, "0"),
            (101, "16"),
            (150, "16"),
            (500, "16"),
            (10000, "16"),
        ]

        for testCase in boundaryTestCases {
            XCTAssertEqual(
                VolumeFormatter.formattedVolumeString(for: testCase.value),
                testCase.expected,
                "formattedVolumeString(for: \(testCase.value)) should be \(testCase.expected)"
            )
        }

        let scalarBoundaryTestCases: [(scalar: CGFloat, expected: String)] = [
            (-1.0, "0"),
            (-0.5, "0"),
            (-0.1, "0"),
            (1.1, "16"),
            (2.0, "16"),
            (10.0, "16"),
        ]

        for testCase in scalarBoundaryTestCases {
            XCTAssertEqual(
                VolumeFormatter.formattedVolumeString(forScalar: testCase.scalar),
                testCase.expected,
                "formattedVolumeString(forScalar: \(testCase.scalar)) should be \(testCase.expected)"
            )
        }
    }

    // MARK: - formatVolumeCount Tests

    func testFormatVolumeCount() {
        let testCases: [(quarterBlocks: CGFloat, expected: String)] = [
            (0.0, "0"),
            (0.25, "1/4"),
            (0.5, "2/4"),
            (0.75, "3/4"),
            (1.0, "1"),
            (8.0, "8"),
            (16.0, "16"),
            (8.25, "8+1/4"),
            (4.5, "4+2/4"),
            (12.75, "12+3/4"),
            (7.9995, "8"),
            (8.0005, "8"),
            (0.2499, "1/4"),
            (0.2501, "1/4"),
        ]

        for testCase in testCases {
            XCTAssertEqual(
                VolumeFormatter.formatVolumeCount(quarterBlocks: testCase.quarterBlocks),
                testCase.expected,
                "formatVolumeCount(quarterBlocks: \(testCase.quarterBlocks)) should be \(testCase.expected)"
            )
        }
    }

    // MARK: - Consistency Tests

    func testFormattedVolumeStringScalarAndPercentageConsistency() {
        let testCases: [(percentage: Int, scalar: CGFloat)] = [
            (0, 0.0),
            (50, 0.5),
            (100, 1.0),
        ]

        for testCase in testCases {
            let percentResult = VolumeFormatter.formattedVolumeString(for: testCase.percentage)
            let scalarResult = VolumeFormatter.formattedVolumeString(forScalar: testCase.scalar)
            XCTAssertEqual(percentResult, scalarResult)
        }
    }

    func testFormattingCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeFormatter.formattedVolumeString(for: percentage)
        }

        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }

    func testFormattedStringDoesNotContainNil() {
        let formatted = VolumeFormatter.formattedVolumeString(for: 50)

        XCTAssertFalse(formatted.contains("nil"))
        XCTAssertFalse(formatted.contains("NSNumber"))
        XCTAssertFalse(formatted.contains("Optional"))
    }

    // MARK: - Performance

    func testFormattingPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
            }
        }
    }
}

// MARK: - VolumeIconHelper Tests

final class VolumeIconHelperTests: XCTestCase {

    // MARK: - Parameterized Icon Selection Tests

    func testVolumeIconSelection() {
        let testCases: [(percentage: Int, expectedSymbol: String, expectedSize: CGFloat)] = [
            (0, "speaker.slash", VolumeGridConstants.Icons.sizeStatusBar),
            (20, "speaker.wave.1", VolumeGridConstants.Icons.sizeLow),
            (50, "speaker.wave.2", VolumeGridConstants.Icons.sizeMedium),
            (80, "speaker.wave.3", VolumeGridConstants.Icons.sizeHigh),
        ]

        for testCase in testCases {
            let icon = VolumeIconHelper.icon(for: testCase.percentage)
            XCTAssertEqual(
                icon.symbolName, testCase.expectedSymbol,
                "icon(for: \(testCase.percentage)) symbolName should be \(testCase.expectedSymbol)"
            )
            XCTAssertEqual(
                icon.size, testCase.expectedSize,
                "icon(for: \(testCase.percentage)) size should be \(testCase.expectedSize)"
            )
        }
    }

    func testHUDIconSelection() {
        let testCases: [(percentage: Int, expectedSymbol: String, expectedSize: CGFloat)] = [
            (0, "speaker.slash.fill", VolumeGridConstants.Icons.sizeHUDMuted),
            (20, "speaker.wave.1.fill", VolumeGridConstants.Icons.sizeHUDLow),
            (50, "speaker.wave.2.fill", VolumeGridConstants.Icons.sizeHUDMedium),
            (80, "speaker.wave.3.fill", VolumeGridConstants.Icons.sizeHUDHigh),
        ]

        for testCase in testCases {
            let icon = VolumeIconHelper.hudIcon(for: testCase.percentage)
            XCTAssertEqual(
                icon.symbolName, testCase.expectedSymbol,
                "hudIcon(for: \(testCase.percentage)) symbolName should be \(testCase.expectedSymbol)"
            )
            XCTAssertEqual(
                icon.size, testCase.expectedSize,
                "hudIcon(for: \(testCase.percentage)) size should be \(testCase.expectedSize)"
            )
        }
    }

    // MARK: - Boundary Tests (Parameterized)

    func testIconClampsBoundaryValues() {
        let boundaryTestCases: [(percentage: Int, expectedSymbol: String)] = [
            (-1000, "speaker.slash"),
            (-50, "speaker.slash"),
            (-10, "speaker.slash"),
            (0, "speaker.slash"),
            (150, "speaker.wave.3"),
            (10000, "speaker.wave.3"),
        ]

        for testCase in boundaryTestCases {
            let icon = VolumeIconHelper.icon(for: testCase.percentage)
            XCTAssertEqual(
                icon.symbolName, testCase.expectedSymbol,
                "icon(for: \(testCase.percentage)) should clamp to \(testCase.expectedSymbol)"
            )

            let hudIcon = VolumeIconHelper.hudIcon(for: testCase.percentage)
            XCTAssertEqual(
                hudIcon.symbolName, testCase.expectedSymbol + ".fill",
                "hudIcon(for: \(testCase.percentage)) should clamp to \(testCase.expectedSymbol).fill"
            )
        }
    }

    // MARK: - Threshold Tests

    func testIconSelectionAtThresholds() {
        let low = VolumeGridConstants.Audio.volumeLevelLow
        let medium = VolumeGridConstants.Audio.volumeLevelMedium

        XCTAssertEqual(VolumeIconHelper.icon(for: low - 1).symbolName, "speaker.wave.1")
        XCTAssertEqual(VolumeIconHelper.icon(for: low).symbolName, "speaker.wave.2")

        XCTAssertEqual(VolumeIconHelper.icon(for: medium - 1).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: medium).symbolName, "speaker.wave.3")
    }

    // MARK: - Unsupported Device Tests

    func testUnsupportedDeviceIcon() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertEqual(icon.symbolName, "nosign")
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeUnsupported)
    }

    func testUnsupportedIgnoresVolumeLevel() {
        for volume in [0, 25, 50, 75, 100] {
            let icon = VolumeIconHelper.icon(for: volume, isUnsupported: true)
            XCTAssertEqual(icon.symbolName, "nosign")
        }
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

    func testIconSelectionCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeIconHelper.icon(for: percentage)
        }

        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.symbolName.isEmpty })
    }

    // MARK: - Performance

    func testCombinedFormattingAndIconPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeIconHelper.icon(for: i)
            }
        }
    }
}
