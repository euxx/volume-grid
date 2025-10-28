import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var volumeMonitor: VolumeMonitor?
    private var volumeSubscriber: AnyCancellable?
    private var deviceSubscriber: AnyCancellable?
    private var volumeMenuItem: NSMenuItem?
    private var statusBarVolumeView: StatusBarVolumeView?
    private var volumeMenuContentView: VolumeMenuItemView?

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
        volumeSubscriber?.cancel()
        deviceSubscriber?.cancel()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)

        if let button = statusItem?.button {
            // 创建自定义视图，包含图标和进度条
            let statusView = StatusBarVolumeView()
            button.addSubview(statusView)
            NSLayoutConstraint.activate([
                statusView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                statusView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            let initialVolume = volumeMonitor?.volumePercentage ?? 0
            statusView.update(percentage: initialVolume)
            statusBarVolumeView = statusView
        }

        // 创建菜单
        let menu = NSMenu()

        // 添加当前音量显示（包含进度条）
        let volumeItem = NSMenuItem()

        // 创建自定义视图容纳文字和进度条
        let initialVolume = volumeMonitor?.volumePercentage ?? 0
        let initialDevice = volumeMonitor?.currentDevice?.name ?? "未知设备"
        let volumeView = VolumeMenuItemView()
        volumeView.update(
            percentage: initialVolume,
            formattedVolume: formattedVolumeString(for: initialVolume),
            deviceName: initialDevice
        )
        volumeItem.view = volumeView
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)
        volumeMenuItem = volumeItem
        volumeMenuContentView = volumeView

        menu.minimumWidth = max(menu.minimumWidth, volumeView.intrinsicContentSize.width)

        menu.addItem(NSMenuItem.separator())

        // 添加开机启动选项
        let launchAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 添加退出选项
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusMenu = menu

        // 实时更新菜单中的音量和设备显示
        volumeSubscriber = volumeMonitor?.$volumePercentage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                guard let self else { return }

                // 更新菜单栏图标下的进度条
                DispatchQueue.main.async {
                    self.statusBarVolumeView?.update(percentage: volume)
                }

                // 更新菜单中的自定义视图
                if let volumeItem = self.volumeMenuItem,
                   let menuView = self.volumeMenuContentView {
                    let formatted = self.formattedVolumeString(for: volume)
                    let deviceName = self.volumeMonitor?.currentDevice?.name ?? "未知设备"
                    DispatchQueue.main.async {
                        menuView.update(
                            percentage: volume,
                            formattedVolume: formatted,
                            deviceName: deviceName
                        )
                        self.statusMenu?.itemChanged(volumeItem)
                    }
                }
            }

        deviceSubscriber = volumeMonitor?.$currentDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self,
                      let volumeItem = self.volumeMenuItem,
                      let menuView = self.volumeMenuContentView
                else { return }
                let name = device?.name ?? "未知设备"
                let volume = self.volumeMonitor?.volumePercentage ?? 0
                let formatted = self.formattedVolumeString(for: volume)
                menuView.update(
                    percentage: volume,
                    formattedVolume: formatted,
                    deviceName: name
                )
                self.statusMenu?.itemChanged(volumeItem)
            }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func showAbout() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VolumeGrid"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知构建"

        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = "Version：\(version)"
        alert.alertStyle = .informational

        let contactString = NSMutableAttributedString(string: "GitHub")
        let range = (contactString.string as NSString).range(of: "GitHub")
        if range.location != NSNotFound {
            contactString.addAttribute(
                .link,
                value: "https://github.com/euxx/VolumeGrid",
                range: range
            )
        }

        let contactLabel = NSTextField(labelWithAttributedString: contactString)
        contactLabel.allowsEditingTextAttributes = true
        contactLabel.isSelectable = true
        contactLabel.lineBreakMode = .byWordWrapping
        contactLabel.maximumNumberOfLines = 0
        contactLabel.translatesAutoresizingMaskIntoConstraints = false
        alert.accessoryView = contactLabel
        contactLabel.widthAnchor.constraint(equalToConstant: 280).isActive = true

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // 将格数转换为字符串格式（简化为只显示当前音量）
    private func formatVolumeString(quarterBlocks: CGFloat) -> String {
        let integerPart = Int(quarterBlocks)
        let fractionalPart = quarterBlocks - CGFloat(integerPart)
        let epsilon: CGFloat = 0.001

        var fractionString = ""
        if fractionalPart >= epsilon && abs(fractionalPart - 1.0) >= epsilon {
            switch fractionalPart {
            case (0.25 - epsilon)...(0.25 + epsilon):
                fractionString = "1/4"
            case (0.5 - epsilon)...(0.5 + epsilon):
                fractionString = "2/4"
            case (0.75 - epsilon)...(0.75 + epsilon):
                fractionString = "3/4"
            default:
                fractionString = String(format: "%.2f", fractionalPart)
            }
        }

        if fractionString.isEmpty {
            return "\(integerPart)"
        } else if integerPart == 0 {
            return "\(fractionString)"
        } else {
            return "\(integerPart)+\(fractionString)"
        }
    }

    private func formattedVolumeString(for percentage: Int) -> String {
        let clamped = max(0, min(percentage, 100))
        let volumeScalar = CGFloat(clamped) / 100.0
        let totalBlocks = volumeScalar * 16.0
        let quarterBlocks = (totalBlocks * 4).rounded() / 4
        return formatVolumeString(quarterBlocks: quarterBlocks)
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
        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

        return FileManager.default.fileExists(atPath: plistPath.path)
    }

    private func enableLaunchAtLogin() {
        let launchAgentsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: true)

        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

        // 获取应用路径
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
                <string>open</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/eux.volumegrid.stderr</string>
            <key>StandardOutPath</key>
            <string>/tmp/eux.volumegrid.stdout</string>
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
        let plistPath = launchAgentsPath.appendingPathComponent("eux.volumegrid.plist")

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
struct VolumeGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 移除WindowGroup，使应用后台运行
        Settings {
            EmptyView()
        }
    }
}
