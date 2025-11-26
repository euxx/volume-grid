import XCTest

@testable import Volume_Grid

/// Tests for LaunchAtLoginServiceable protocol
/// Uses MockLaunchAtLoginController to avoid system side effects
final class LaunchAtLoginControllerTests: XCTestCase {
    var mockController: MockLaunchAtLoginController!

    override func setUp() {
        super.setUp()
        mockController = MockLaunchAtLoginController()
    }

    override func tearDown() {
        mockController = nil
        super.tearDown()
    }

    // MARK: - LaunchAtLoginError Tests

    func testLaunchAtLoginErrorMessage() {
        let error = LaunchAtLoginError.message("Test error")
        XCTAssertEqual(error.errorDescription, "Test error")
    }

    func testLaunchAtLoginErrorWithSpecialCharacters() {
        let message = "Failed: invalid path"
        let error = LaunchAtLoginError.message(message)
        XCTAssertEqual(error.errorDescription, message)
    }

    func testLaunchAtLoginErrorWithEmptyMessage() {
        let error = LaunchAtLoginError.message("")
        XCTAssertEqual(error.errorDescription, "")
    }

    // MARK: - isEnabled() Tests

    func testIsEnabledReturnsBool() {
        let _ = mockController.isEnabled()
    }

    func testIsEnabledCallableMultipleTimes() {
        let _ = mockController.isEnabled()
        let _ = mockController.isEnabled()
    }

    func testIsEnabledReturnsInitialFalse() {
        XCTAssertFalse(mockController.isEnabled())
    }

    func testIsEnabledReturnsSetValue() {
        mockController.isEnabledValue = true
        XCTAssertTrue(mockController.isEnabled())

        mockController.isEnabledValue = false
        XCTAssertFalse(mockController.isEnabled())
    }

    // MARK: - setEnabled() Tests

    func testSetEnabledToTrueCallsCompletion() {
        let expectation = XCTestExpectation(description: "Enable completion")

        mockController.setEnabled(true) { result in
            switch result {
            case .success, .failure:
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledToFalseCallsCompletion() {
        let expectation = XCTestExpectation(description: "Disable completion")

        mockController.setEnabled(false) { result in
            switch result {
            case .success, .failure:
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledReturnsSuccess() {
        let expectation = XCTestExpectation(description: "Result returned")

        mockController.setEnabled(true) { result in
            switch result {
            case .success(let value):
                XCTAssertTrue(value)
                expectation.fulfill()
            case .failure:
                XCTFail("Expected success")
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledUpdatesState() {
        let expectation = XCTestExpectation(description: "State updated")

        mockController.setEnabled(true) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mockController.isEnabled())
    }

    func testSetEnabledMultipleTimesWithDifferentValues() {
        let expectation1 = XCTestExpectation(description: "First call")
        let expectation2 = XCTestExpectation(description: "Second call")

        mockController.setEnabled(true) { _ in
            expectation1.fulfill()
        }

        mockController.setEnabled(false) { _ in
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)
        XCTAssertFalse(mockController.isEnabled())
    }

    func testSetEnabledExecutesAsynchronously() {
        let expectation = XCTestExpectation(description: "Async execution")
        var callCount = 0

        mockController.setEnabled(true) { _ in
            callCount += 1
            expectation.fulfill()
        }

        XCTAssertEqual(callCount, 0)
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(callCount, 1)
    }

    func testSetEnabledCallsCompletionOnMainThread() {
        let expectation = XCTestExpectation(description: "Main thread")
        var executedOnMainThread = false

        mockController.setEnabled(true) { _ in
            executedOnMainThread = Thread.isMainThread
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(executedOnMainThread)
    }

    func testSetEnabledWithCustomClosure() {
        let expectation = XCTestExpectation(description: "Custom closure")
        var customClosureCalled = false

        mockController.setEnabledClosure = { enabled, completion in
            customClosureCalled = true
            XCTAssertTrue(enabled)
            completion(.success(enabled))
        }

        mockController.setEnabled(true) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(customClosureCalled)
    }

    func testSetEnabledWithCustomErrorClosure() {
        let expectation = XCTestExpectation(description: "Custom error closure")

        mockController.setEnabledClosure = { enabled, completion in
            completion(.failure(.message("Custom error")))
        }

        mockController.setEnabled(true) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure(let error):
                XCTAssertEqual(error.errorDescription, "Custom error")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testSetEnabledExpectation() {
        let expectation = XCTestExpectation(description: "Expectation called")
        var enabledValue: Bool?

        mockController.setEnabledExpectation = { enabled in
            enabledValue = enabled
            expectation.fulfill()
        }

        mockController.setEnabled(true) { _ in }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(enabledValue, true)
    }
}
