import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var volumeMonitor: VolumeMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为辅助应用，不显示在Dock中
        NSApplication.shared.setActivationPolicy(.accessory)

        // 创建音量监听器
        volumeMonitor = VolumeMonitor()
        volumeMonitor?.startListening()
        volumeMonitor?.getAudioDevices()

        // 创建菜单栏图标
        setupStatusBarItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeMonitor?.stopListening()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Sound Monitor")
            button.image?.isTemplate = true // 使其适应菜单栏主题
        }

        // 创建菜单
        let menu = NSMenu()

        // 添加当前音量显示
        let volumeItem = NSMenuItem()
        volumeItem.title = "当前音量: \(volumeMonitor?.volumePercentage ?? 0)%"
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)

        // 添加当前设备显示
        let deviceItem = NSMenuItem()
        deviceItem.title = "当前设备: \(volumeMonitor?.currentDevice?.name ?? "未知设备")"
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)

        menu.addItem(NSMenuItem.separator())

        // 添加开机启动选项
        let launchAtLoginItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // 添加退出选项
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // 设置定时器更新菜单中的音量显示
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            if let volume = self?.volumeMonitor?.volumePercentage {
                volumeItem.title = "当前音量: \(volume)%"
            }
            if let deviceName = self?.volumeMonitor?.currentDevice?.name {
                deviceItem.title = "当前设备: \(deviceName)"
            } else {
                deviceItem.title = "当前设备: 未知设备"
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = isLaunchAtLoginEnabled()
        if enabled {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
        // 更新菜单状态
        if let menu = statusItem?.menu,
           let launchItem = menu.items.first(where: { $0.title == "开机启动" }) {
            launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsPath.appendingPathComponent("eux.sound.plist")

        return FileManager.default.fileExists(atPath: plistPath.path)
    }

    private func enableLaunchAtLogin() {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: true)

        let plistPath = launchAgentsPath.appendingPathComponent("eux.sound.plist")

        // 获取应用路径
        let appPath = Bundle.main.bundlePath

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>eux.sound</string>
            <key>ProgramArguments</key>
            <array>
                <string>open</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/eux.sound.stderr</string>
            <key>StandardOutPath</key>
            <string>/tmp/eux.sound.stdout</string>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            // 加载Launch Agent
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistPath.path]
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to enable launch at login: \(error)")
        }
    }

    private func disableLaunchAtLogin() {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = launchAgentsPath.appendingPathComponent("eux.sound.plist")

        do {
            // 卸载Launch Agent
            let unloadProcess = Process()
            unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProcess.arguments = ["unload", plistPath.path]
            try unloadProcess.run()
            unloadProcess.waitUntilExit()

            // 删除plist文件
            try FileManager.default.removeItem(at: plistPath)
        } catch {
            print("Failed to disable launch at login: \(error)")
        }
    }
}

@main
struct VolumeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 移除WindowGroup，使应用后台运行
        Settings {
            EmptyView()
        }
    }
}
