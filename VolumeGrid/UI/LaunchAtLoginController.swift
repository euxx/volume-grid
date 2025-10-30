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

/// Coordinates enabling/disabling launch at login, hiding legacy details from callers.
final class LaunchAtLoginController {
    private let queue = DispatchQueue(label: "com.volumegrid.launchAtLogin", qos: .userInitiated)

    func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")
            let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")
            return FileManager.default.fileExists(atPath: plistPath.path)
        }
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

    // MARK: - Modern APIs

    @available(macOS 13.0, *)
    private func enableModern() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.register()
            return .success(true)
        } catch {
            return .failure(
                .message("Failed to enable launch at login: \(error.localizedDescription)"))
        }
    }

    @available(macOS 13.0, *)
    private func disableModern() -> Result<Bool, LaunchAtLoginError> {
        do {
            try SMAppService.mainApp.unregister()
            return .success(false)
        } catch {
            return .failure(
                .message("Failed to disable launch at login: \(error.localizedDescription)"))
        }
    }

    // MARK: - Legacy APIs

    private func enableLegacy() -> Result<Bool, LaunchAtLoginError> {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

        do {
            try FileManager.default.createDirectory(
                at: launchAgentsPath, withIntermediateDirectories: true)
        } catch {
            return .failure(
                .message("Failed to create LaunchAgents directory: \(error.localizedDescription)")
            )
        }

        let appPath = Bundle.main.bundlePath
        let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>eux.volumegrid</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """

        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure(
                .message("Failed to write LaunchAgent plist: \(error.localizedDescription)"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(
                .message("Failed to register LaunchAgent: \(error.localizedDescription)")
            )
        }

        guard process.terminationStatus == 0 else {
            return .failure(.message("launchctl returned exit code \(process.terminationStatus)"))
        }

        return .success(true)
    }

    private func disableLegacy() -> Result<Bool, LaunchAtLoginError> {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

        let unloadProcess = Process()
        unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unloadProcess.arguments = ["unload", plistPath.path]

        do {
            try unloadProcess.run()
            unloadProcess.waitUntilExit()
        } catch {
            return .failure(
                .message("Failed to unload LaunchAgent: \(error.localizedDescription)")
            )
        }

        if unloadProcess.terminationStatus != 0 {
            return .failure(
                .message("launchctl returned exit code \(unloadProcess.terminationStatus)"))
        }

        do {
            if FileManager.default.fileExists(atPath: plistPath.path) {
                try FileManager.default.removeItem(at: plistPath)
            }
        } catch {
            return .failure(
                .message("Failed to remove LaunchAgent plist: \(error.localizedDescription)"))
        }

        return .success(false)
    }

    // MARK: - Entry points

    private func enable() -> Result<Bool, LaunchAtLoginError> {
        if #available(macOS 13.0, *) {
            return enableModern()
        } else {
            return enableLegacy()
        }
    }

    private func disable() -> Result<Bool, LaunchAtLoginError> {
        if #available(macOS 13.0, *) {
            return disableModern()
        } else {
            return disableLegacy()
        }
    }
}
