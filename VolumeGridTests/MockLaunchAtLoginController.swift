import Foundation
import os.lock

@testable import VolumeGrid

/// Mock implementation of LaunchAtLoginServiceable for testing
/// Allows tests to control behavior without affecting system settings
final class MockLaunchAtLoginController: LaunchAtLoginServiceable {
    private let _isEnabled = OSAllocatedUnfairLock(initialState: false)
    var isEnabledValue: Bool {
        get { _isEnabled.withLock { $0 } }
        set { _isEnabled.withLock { $0 = newValue } }
    }

    // Configured during test setUp only — no concurrent access
    nonisolated(unsafe) var setEnabledExpectation: ((Bool) -> Void)?
    nonisolated(unsafe) var setEnabledClosure:
        ((Bool, @escaping @Sendable (Result<Bool, LaunchAtLoginError>) -> Void) -> Void)?

    nonisolated func isEnabled() -> Bool {
        isEnabledValue
    }

    nonisolated func setEnabled(
        _ enabled: Bool,
        completion: @escaping @Sendable (Result<Bool, LaunchAtLoginError>) -> Void
    ) {
        setEnabledExpectation?(enabled)

        if let closure = setEnabledClosure {
            closure(enabled, completion)
        } else {
            // Default behavior: simulate successful update
            isEnabledValue = enabled
            DispatchQueue.main.async {
                completion(.success(enabled))
            }
        }
    }
}
