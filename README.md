# sound


macOS Tohoe 26 改变了系统音量调节弹窗的样式，只在激活显示器右上角显示音量弹窗，且样式简化为单一条形显示，缺少了经典的16个方格显示音量级别的视觉反馈。

音量调节显示弹窗，这个项目是为了恢复原有的音量调节弹窗样式，并且加上了 macOS Tohoe 26 中当前输出设备显示的功能。
适用于经常调节音量、有多显示器需求的用户。

## 功能特性

- 🎵 恢复经典的音量弹窗样式
- 🖥️ 支持多显示器显示
- 📊 16个方格显示音量级别，支持以 1/4 格为单位的细粒度变化
- 🔄 自动监听设备切换，切换后显示音量弹窗(如蓝牙耳机连上时)
- 📱 菜单栏图标控制
- 🔄 开机自动启动

## todos

- 黑暗模式适配/浅色模式适配 / 根据背景色调整弹窗 hub 颜色
- 支持静音图标显示
- 开源许可证选择
- 国际化支持
- 应用图标
- 开启启动功能生效

## 使用方法

1. 运行应用后，应用将在后台运行
2. 菜单栏会出现音量图标
3. 调节音量时会显示经典样式的弹窗
4. 点击菜单栏图标可查看当前音量和当前输出设备
5. 可设置开机自动启动

## 构建 .app

1. 安装 Xcode (14+)，并打开 `sound.xcodeproj`
2. 在 Xcode 中选择 `sound` scheme，`Any Mac (Intel/Apple Silicon)` 目标
3. 选择菜单 `Product > Archive` 或执行 `⌘⇧B` 进行 Release 构建
4. 构建完成后 `.app` 会出现在 `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/sound.app`
5. 你也可以使用命令行快速生成（将派生数据固定到下载目录）：
   ```bash
   xcodebuild \
     -project sound.xcodeproj \
     -scheme sound \
     -configuration Release \
     -derivedDataPath ~/Downloads/sound-build
   ```
   完成后 `.app` 位于 `~/Downloads/sound-build/Build/Products/Release/sound.app`
6. 若使用 Xcode GUI，可在 `Xcode > Settings... > Locations > Derived Data` 中选择 `Custom`, 将路径设置到 `~/Downloads/sound-build`，然后执行 `Product > Archive`，输出同样会落在下载目录

## 运行方式

- 双击 `.app`，或使用 `open build/Build/Products/Release/sound.app`
- 在 Xcode 中选择 `Product > Run`（快捷键 `⌘R`），可以直接调试运行
