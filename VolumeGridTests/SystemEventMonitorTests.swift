import XCTest

@testable import VolumeGrid

// MARK: - SystemEventMonitor Key Parsing Tests

final class SystemEventMonitorParsingTests: XCTestCase {

    // NX key event data1 format:
    // Bits 31-16: keyCode
    // Bits 15-8:  keyState (0xA = key down)
    // Bits 7-0:   keyRepeat flag

    /// Build a data1 value for a given keyCode with keyState = 0xA (key down).
    private func makeData1(keyCode: Int, keyState: Int = 0x0A) -> Int {
        (keyCode << 16) | (keyState << 8)
    }

    // MARK: - Volume Up (keyCode 0)

    func testParseVolumeUp() {
        let data1 = makeData1(keyCode: 0)
        XCTAssertEqual(SystemEventMonitor.parseVolumeKey(data1: data1), .up)
    }

    // MARK: - Volume Down (keyCode 1)

    func testParseVolumeDown() {
        let data1 = makeData1(keyCode: 1)
        XCTAssertEqual(SystemEventMonitor.parseVolumeKey(data1: data1), .down)
    }

    // MARK: - Mute (keyCode 7)

    func testParseMute() {
        let data1 = makeData1(keyCode: 7)
        XCTAssertEqual(SystemEventMonitor.parseVolumeKey(data1: data1), .mute)
    }

    // MARK: - Non-volume keys

    func testParseUnknownKeyCodeReturnsNil() {
        let data1 = makeData1(keyCode: 3)  // brightness up
        XCTAssertNil(SystemEventMonitor.parseVolumeKey(data1: data1))
    }

    func testParseKeyCode2ReturnsNil() {
        let data1 = makeData1(keyCode: 2)  // not a volume key
        XCTAssertNil(SystemEventMonitor.parseVolumeKey(data1: data1))
    }

    // MARK: - Wrong keyState

    func testWrongKeyStateReturnsNil() {
        // keyState 0x0B instead of 0x0A (key up, not key down)
        let data1 = makeData1(keyCode: 0, keyState: 0x0B)
        XCTAssertNil(SystemEventMonitor.parseVolumeKey(data1: data1))
    }

    func testZeroKeyStateReturnsNil() {
        let data1 = makeData1(keyCode: 0, keyState: 0x00)
        XCTAssertNil(SystemEventMonitor.parseVolumeKey(data1: data1))
    }

    // MARK: - Key repeat (lower bits should not affect keyCode)

    func testKeyRepeatBitsIgnored() {
        // Add repeat flag in lower byte — should still parse correctly
        let data1 = makeData1(keyCode: 0) | 0x01
        XCTAssertEqual(SystemEventMonitor.parseVolumeKey(data1: data1), .up)
    }

    // MARK: - Edge cases

    func testZeroData1ReturnsNil() {
        // keyState = 0 → fails guard
        XCTAssertNil(SystemEventMonitor.parseVolumeKey(data1: 0))
    }

    func testLargeKeyCodeMaskedCorrectly() {
        // keyCode 256 (0x100) — only lower 8 bits considered after & 0xFF
        // 0x100 & 0xFF = 0 → should be .up
        let data1 = makeData1(keyCode: 0x100)
        XCTAssertEqual(SystemEventMonitor.parseVolumeKey(data1: data1), .up)
    }
}
