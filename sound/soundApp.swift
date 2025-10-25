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
    private var deviceMenuItem: NSMenuItem?
    private var statusBarButton: NSView?
    private var progressBarView: NSView?

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
            let customView = createStatusBarCustomView(percentage: volumeMonitor?.volumePercentage ?? 0)
            button.addSubview(customView)
            statusBarButton = customView
            progressBarView = customView.subviews.last  // 保存进度条视图的引用
        }

        // 创建菜单
        let menu = NSMenu()

        // 添加当前音量显示（包含进度条）
        let volumeItem = NSMenuItem()

        // 创建自定义视图容纳文字和进度条
        let volumeView = createVolumeMenuItemView(percentage: volumeMonitor?.volumePercentage ?? 0)
        volumeItem.view = volumeView
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)
        volumeMenuItem = volumeItem

        // 添加当前设备显示
        let deviceItem = NSMenuItem()
        deviceItem.title = "当前设备: \(volumeMonitor?.currentDevice?.name ?? "未知设备")"
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)
        deviceMenuItem = deviceItem

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
        statusMenu = menu

        // 实时更新菜单中的音量和设备显示
        volumeSubscriber = volumeMonitor?.$volumePercentage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                guard let self else { return }

                // 更新菜单栏图标下的进度条
                if let button = self.statusItem?.button {
                    button.subviews.forEach { $0.removeFromSuperview() }
                    let customView = self.createStatusBarCustomView(percentage: volume)
                    button.addSubview(customView)
                    self.statusBarButton = customView
                }

                // 更新菜单中的自定义视图
                if let volumeItem = self.volumeMenuItem {
                    let volumeView = self.createVolumeMenuItemView(percentage: volume)
                    volumeItem.view = volumeView
                    self.statusMenu?.itemChanged(volumeItem)
                }
            }

        deviceSubscriber = volumeMonitor?.$currentDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self, let deviceItem = self.deviceMenuItem else { return }
                let name = device?.name ?? "未知设备"
                deviceItem.title = "当前设备: \(name)"
                self.statusMenu?.itemChanged(deviceItem)
            }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func createStatusBarCustomView(percentage: Int) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 22))

        // 图标
        let iconName = percentage == 0 ? "speaker.slash" : "speaker.wave.2"
        let speakerImage = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
        let imageView = NSImageView(image: speakerImage!)
        imageView.frame = NSRect(x: 2, y: 3, width: 16, height: 16)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = NSColor.controlTextColor

        // 进度条背景（位于图标下方）
        let progressBackgroundView = NSView(frame: NSRect(x: 3, y: 1, width: 14, height: 2))
        progressBackgroundView.wantsLayer = true
        progressBackgroundView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.3).cgColor
        progressBackgroundView.layer?.cornerRadius = 1

        // 进度条填充
        let progressWidth = CGFloat(percentage) / 100.0 * 14.0
        let progressView = NSView(frame: NSRect(x: 3, y: 1, width: progressWidth, height: 2))
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.systemGray.cgColor
        progressView.layer?.cornerRadius = 1

        container.addSubview(progressBackgroundView)
        container.addSubview(progressView)
        container.addSubview(imageView)

        return container
    }

    private func createVolumeMenuItemView(percentage: Int) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 50))

        // 文字标签
        let label = NSTextField(labelWithString: "当前音量: \(percentage)%")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.frame = NSRect(x: 10, y: 28, width: 230, height: 16)

        // 进度条背景
        let progressBackgroundView = NSView(frame: NSRect(x: 10, y: 8, width: 230, height: 4))
        progressBackgroundView.wantsLayer = true
        progressBackgroundView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        progressBackgroundView.layer?.cornerRadius = 2

        // 进度条填充
        let progressWidth = CGFloat(percentage) / 100.0 * 230.0
        let progressView = NSView(frame: NSRect(x: 10, y: 8, width: progressWidth, height: 4))
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.systemGray.cgColor
        progressView.layer?.cornerRadius = 2

        container.addSubview(label)
        container.addSubview(progressBackgroundView)
        container.addSubview(progressView)

        return container
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
