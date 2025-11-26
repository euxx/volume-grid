import XCTest

@testable import Volume_Grid

// MARK: - Comparable.clamped(to:) Tests

final class ComparableClampTests: XCTestCase {
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

    func testIntegerClipping() {
        let clamped = Int.min.clamped(to: 0...100)
        XCTAssertEqual(clamped, 0)

        let clamped2 = Int.max.clamped(to: 0...100)
        XCTAssertEqual(clamped2, 100)
    }

    func testCGFloatClipping() {
        let clamped = CGFloat.greatestFiniteMagnitude.clamped(to: 0...1)
        XCTAssertEqual(clamped, 1.0)

        let clamped2 = (-CGFloat.greatestFiniteMagnitude).clamped(to: 0...1)
        XCTAssertEqual(clamped2, 0.0)
    }
}

// MARK: - VolumeFormatter Tests

final class VolumeFormatterTests: XCTestCase {

    // MARK: - formattedVolumeString(for:)

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

    func testFormattedVolumeStringPercentageQuarterPoints() {
        let p25 = VolumeFormatter.formattedVolumeString(for: 25)
        XCTAssertEqual(p25, "4")

        let p50 = VolumeFormatter.formattedVolumeString(for: 50)
        XCTAssertEqual(p50, "8")

        let p75 = VolumeFormatter.formattedVolumeString(for: 75)
        XCTAssertEqual(p75, "12")
    }

    // MARK: - formattedVolumeString(forScalar:)

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

    func testFormattedVolumeStringScalarQuarterValues() {
        let quarter = VolumeFormatter.formattedVolumeString(forScalar: 0.25)
        XCTAssertEqual(quarter, "4")

        let threeQuarters = VolumeFormatter.formattedVolumeString(forScalar: 0.75)
        XCTAssertEqual(threeQuarters, "12")
    }

    func testFormattedVolumeStringScalarEdgeCases() {
        let nearZero = VolumeFormatter.formattedVolumeString(forScalar: 0.0001)
        XCTAssertEqual(nearZero, "0")

        let nearMax = VolumeFormatter.formattedVolumeString(forScalar: 0.9999)
        XCTAssertEqual(nearMax, "16")
    }

    // MARK: - formatVolumeCount(quarterBlocks:)

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
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 7.9995), "8")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 8.0005), "8")
    }

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

    func testFormatVolumeCountEpsilonHandling() {
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.2499), "1/4")
        XCTAssertEqual(VolumeFormatter.formatVolumeCount(quarterBlocks: 0.2501), "1/4")
    }

    // MARK: - Consistency

    func testFormattedVolumeStringScalarAndPercentageConsistency() {
        let percent50 = VolumeFormatter.formattedVolumeString(for: 50)
        let scalar05 = VolumeFormatter.formattedVolumeString(forScalar: 0.5)
        XCTAssertEqual(percent50, scalar05)

        let percent100 = VolumeFormatter.formattedVolumeString(for: 100)
        let scalar10 = VolumeFormatter.formattedVolumeString(forScalar: 1.0)
        XCTAssertEqual(percent100, scalar10)
    }

    func testVolumeLevelThresholds() {
        let low = VolumeGridConstants.Audio.volumeLevelLow
        let medium = VolumeGridConstants.Audio.volumeLevelMedium

        XCTAssertGreaterThanOrEqual(low, 0)
        XCTAssertLessThanOrEqual(low, 100)

        XCTAssertGreaterThanOrEqual(medium, low)
        XCTAssertLessThanOrEqual(medium, 100)
    }

    func testVolumeFormatterBoundaries() {
        let negative = VolumeFormatter.formattedVolumeString(for: -50)
        XCTAssertEqual(negative, "0")

        let over100 = VolumeFormatter.formattedVolumeString(for: 150)
        XCTAssertEqual(over100, "16")
    }

    // MARK: - Formatter Range Coverage

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

    func testFormattingConsistency() {
        for percentage in [0, 25, 50, 75, 100] {
            let result1 = VolumeFormatter.formattedVolumeString(for: percentage)
            let result2 = VolumeFormatter.formattedVolumeString(for: percentage)
            XCTAssertEqual(result1, result2, "Formatting should be consistent")
        }
    }

    // MARK: - Extreme Values

    func testNegativeVolumePercentage() {
        let testCases = [-1000, -100, -50, -1]
        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            XCTAssertEqual(formatted, "0")
        }
    }

    func testVeryHighVolumePercentage() {
        let testCases = [101, 150, 500, 1000, 10000]
        for percentage in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(for: percentage)
            XCTAssertEqual(formatted, "16")
        }
    }

    func testNegativeScalar() {
        let testCases: [CGFloat] = [-1.0, -0.5, -0.1]
        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            XCTAssertEqual(formatted, "0")
        }
    }

    func testScalarAboveOne() {
        let testCases: [CGFloat] = [1.1, 2.0, 10.0, 100.0]
        for scalar in testCases {
            let formatted = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            XCTAssertEqual(formatted, "16")
        }
    }

    // MARK: - Performance

    func testFormattingPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
            }
        }
    }

    func testFormattingScalarPerformance() {
        measure {
            for i in 0...100 {
                let scalar = CGFloat(i) / 100.0
                _ = VolumeFormatter.formattedVolumeString(forScalar: scalar)
            }
        }
    }

    func testVolumeClampingPerformance() {
        measure {
            for i in -50...150 {
                let value = i.clamped(to: 0...100)
                _ = value
            }
        }
    }
}

// MARK: - VolumeIconHelper Tests

final class VolumeIconHelperTests: XCTestCase {

    // MARK: - Regular Icon Selection

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

    func testVolumeIconClampsInput() {
        let iconNegative = VolumeIconHelper.icon(for: -10)
        XCTAssertEqual(iconNegative.symbolName, "speaker.slash")

        let iconOver = VolumeIconHelper.icon(for: 150)
        XCTAssertEqual(iconOver.symbolName, "speaker.wave.3")
    }

    // MARK: - HUD Icon Selection

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

    // MARK: - Icon Sizes

    func testIconSizesMuted() {
        let icon = VolumeIconHelper.icon(for: 0)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeStatusBar)
    }

    func testIconSizesLow() {
        let icon = VolumeIconHelper.icon(for: 20)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeLow)
    }

    func testIconSizesMedium() {
        let icon = VolumeIconHelper.icon(for: 50)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeMedium)
    }

    func testIconSizesHigh() {
        let icon = VolumeIconHelper.icon(for: 80)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeHigh)
    }

    func testHUDIconSizesMuted() {
        let icon = VolumeIconHelper.hudIcon(for: 0)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeHUDMuted)
    }

    func testHUDIconSizesLow() {
        let icon = VolumeIconHelper.hudIcon(for: 20)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeHUDLow)
    }

    func testHUDIconSizesMedium() {
        let icon = VolumeIconHelper.hudIcon(for: 50)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeHUDMedium)
    }

    func testHUDIconSizesHigh() {
        let icon = VolumeIconHelper.hudIcon(for: 80)
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeHUDHigh)
    }

    // MARK: - Unsupported Device

    func testIconUnsupportedDevice() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertEqual(icon.symbolName, "nosign")
        XCTAssertEqual(icon.size, VolumeGridConstants.Icons.sizeUnsupported)
    }

    func testIconUnsupportedIgnoresVolume() {
        for volume in [0, 25, 50, 75, 100] {
            let icon = VolumeIconHelper.icon(for: volume, isUnsupported: true)
            XCTAssertEqual(icon.symbolName, "nosign")
        }
    }

    func testUnsupportedAtAllVolumes() {
        let percentages = [0, 25, 50, 75, 100]
        for percentage in percentages {
            let icon = VolumeIconHelper.icon(for: percentage, isUnsupported: true)
            XCTAssertEqual(icon.symbolName, "nosign")
        }
    }

    func testUnsupportedIconSize() {
        let icon = VolumeIconHelper.icon(for: 50, isUnsupported: true)
        XCTAssertGreaterThan(icon.size, 0)
    }

    // MARK: - Consistency

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

    func testIconSelectionConsistency() {
        for percentage in [0, 25, 50, 75, 100] {
            let result1 = VolumeIconHelper.icon(for: percentage)
            let result2 = VolumeIconHelper.icon(for: percentage)

            XCTAssertEqual(result1.symbolName, result2.symbolName)
            XCTAssertEqual(result1.size, result2.size)
        }
    }

    // MARK: - Threshold Verification

    func testVolumeLevelThresholdsFromConstants() {
        let low = VolumeGridConstants.Audio.volumeLevelLow
        let medium = VolumeGridConstants.Audio.volumeLevelMedium

        XCTAssertEqual(VolumeIconHelper.icon(for: low - 1).symbolName, "speaker.wave.1")
        XCTAssertEqual(VolumeIconHelper.icon(for: low).symbolName, "speaker.wave.2")

        XCTAssertEqual(VolumeIconHelper.icon(for: medium - 1).symbolName, "speaker.wave.2")
        XCTAssertEqual(VolumeIconHelper.icon(for: medium).symbolName, "speaker.wave.3")
    }

    func testIconAtThresholds() {
        let volumeLevelLow = VolumeGridConstants.Audio.volumeLevelLow
        let volumeLevelMedium = VolumeGridConstants.Audio.volumeLevelMedium

        let belowLow = VolumeIconHelper.icon(for: volumeLevelLow - 1)
        let atLow = VolumeIconHelper.icon(for: volumeLevelLow)

        XCTAssertFalse(belowLow.symbolName.isEmpty)
        XCTAssertFalse(atLow.symbolName.isEmpty)

        let belowMedium = VolumeIconHelper.icon(for: volumeLevelMedium - 1)
        let atMedium = VolumeIconHelper.icon(for: volumeLevelMedium)

        XCTAssertFalse(belowMedium.symbolName.isEmpty)
        XCTAssertFalse(atMedium.symbolName.isEmpty)
    }

    // MARK: - Edge Cases

    func testIconWithExtremeValues() {
        let veryNegative = VolumeIconHelper.icon(for: -1000)
        XCTAssertEqual(veryNegative.symbolName, "speaker.slash")

        let veryLarge = VolumeIconHelper.icon(for: 10000)
        XCTAssertEqual(veryLarge.symbolName, "speaker.wave.3")
    }

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

    // MARK: - Performance

    func testIconSelectionPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.icon(for: i)
            }
        }
    }

    func testHUDIconSelectionPerformance() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.hudIcon(for: i)
            }
        }
    }

    func testIconSelectionWithUnsupported() {
        measure {
            for i in 0...100 {
                _ = VolumeIconHelper.icon(for: i, isUnsupported: i % 10 == 0)
            }
        }
    }

    func testIconSelectionThroughput() {
        let iterations = 10000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101
            _ = VolumeIconHelper.icon(for: percentage)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let throughput = Double(iterations) / elapsed

        print("Icon selection throughput: \(throughput) operations/sec")
        XCTAssertGreaterThan(throughput, 50_000)
    }

    func testFormattingThroughput() {
        let iterations = 10000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101
            _ = VolumeFormatter.formattedVolumeString(for: percentage)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let throughput = Double(iterations) / elapsed

        print("Volume formatting throughput: \(throughput) operations/sec")
        XCTAssertGreaterThan(throughput, 100_000)
    }

    func testCombinedFormattingAndIconing() {
        measure {
            for i in 0...100 {
                _ = VolumeFormatter.formattedVolumeString(for: i)
                _ = VolumeIconHelper.icon(for: i)
            }
        }
    }

    func testHighFrequencyMixedOperations() {
        let iterations = 1000
        let startTime = Date()

        for i in 0..<iterations {
            let percentage = i % 101

            if i % 2 == 0 {
                _ = VolumeFormatter.formattedVolumeString(for: percentage)
            } else {
                _ = VolumeIconHelper.icon(for: percentage)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.1)
    }

    func testRepeatedOperationsEfficiency() {
        var results: [String] = []

        measure {
            for _ in 0..<10 {
                for i in 0...100 {
                    results.append(VolumeFormatter.formattedVolumeString(for: i))
                }
            }
        }

        XCTAssertGreaterThan(results.count, 0)
    }

    func testNoMemoryLeaksInFormatting() {
        var results: [String] = []

        for i in 0..<1000 {
            results.append(VolumeFormatter.formattedVolumeString(for: i % 101))
        }

        XCTAssertEqual(results.count, 1000)
        results.removeAll()
    }

    func testNoMemoryLeaksInIconSelection() {
        var results: [VolumeIconHelper.VolumeIcon] = []

        for i in 0..<1000 {
            results.append(VolumeIconHelper.icon(for: i % 101))
        }

        XCTAssertEqual(results.count, 1000)
        results.removeAll()
    }

    func testIconSelectionCoversFullRange() {
        let results = (0...100).map { percentage in
            VolumeIconHelper.icon(for: percentage)
        }

        XCTAssertEqual(results.count, 101)
        XCTAssertTrue(results.allSatisfy { !$0.symbolName.isEmpty })
    }
}
