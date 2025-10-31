import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

final class LaunchAtLoginController {
    private let queue = DispatchQueue(label: "com.volumegrid.launchAtLogin", qos: .userInitiated)

    func isEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, LaunchAtLoginError>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let result: Result<Bool, LaunchAtLoginError>
            if enabled {
                result = self.enable()
            } else {
                result = self.disable()
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func enable() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.register()
            return .success(true)
        } catch {
            return .failure(
                .message("Failed to enable launch at login: \(error.localizedDescription)"))
        }
    }

    private func disable() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.unregister()
            return .success(false)
        } catch {
            return .failure(
                .message("Failed to disable launch at login: \(error.localizedDescription)"))
        }
    }
}
