# VolumeGrid


macOS Tohoe 26 改变了系统音量调节弹窗的样式，只在激活显示器右上角显示音量弹窗，且样式简化为单一条形显示，缺少了经典的16个方格显示音量级别的视觉反馈。

音量调节显示弹窗，这个项目（VolumeGrid）是为了恢复原有的音量调节弹窗样式，并且加上了 macOS Tohoe 26 中当前输出设备显示的功能。
适用于经常调节音量、有多显示器需求的用户。

## 功能特性

- 🎵 恢复经典的音量弹窗样式
- 🖥️ 支持多显示器显示
- 📊 16个方格显示音量级别，支持以 1/4 格为单位的细粒度变化
- 🔄 自动监听设备切换，切换后显示音量弹窗(如蓝牙耳机连上时)
- 📱 菜单栏图标控制
- 🔄 开机自动启动

## todos

- [x] 黑暗模式适配/浅色模式适配 / 根据背景色调整弹窗 hub 颜色
- [x] 支持静音图标显示
- [ ] 开源许可证选择
- [x] Github Action 自动构建发布
- [ ] 国际化支持
- [ ] 应用图标
- [ ] 开机启动功能生效
- [x] 关于 - 显示应用版本、联系方式等信息
- [x] 重命名
- [ ] 所有中文内容替换为英文
- [ ] Linters, type checkers, auto-formatters

## 使用方法

1. 运行应用后，应用将在后台运行
2. 菜单栏会出现音量图标
3. 调节音量时会显示经典样式的弹窗
4. 点击菜单栏图标可查看当前音量和当前输出设备
5. 可设置开机自动启动

## 构建 .app

1. 安装 Xcode (14+)，并打开 `VolumeGrid.xcodeproj`
2. 在 Xcode 中选择 `VolumeGrid` scheme，`Any Mac (Intel/Apple Silicon)` 目标
3. 选择菜单 `Product > Archive` 或执行 `⌘⇧B` 进行 Release 构建
4. 构建完成后 `.app` 会出现在 `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/VolumeGrid.app`
5. 你也可以使用命令行快速生成（将派生数据固定到下载目录）：
   ```bash
   xcodebuild \
     -project VolumeGrid.xcodeproj \
     -scheme VolumeGrid \
     -configuration Release \
     -derivedDataPath ~/Downloads/volumegrid-build
   ```
   完成后 `.app` 位于 `~/Downloads/volumegrid-build/Build/Products/Release/VolumeGrid.app`
6. 若使用 Xcode GUI，可在 `Xcode > Settings... > Locations > Derived Data` 中选择 `Custom`, 将路径设置到 `~/Downloads/volumegrid-build`，然后执行 `Product > Archive`，输出同样会落在下载目录

## 自动化构建发布

- 推送 `v*` 格式的标签（例如 `v0.1.0`）到远程仓库会自动触发 GitHub Action
- CI 会在 macOS runner 上使用 Xcode 15.4 执行 Release 构建
- 构建完成后会把 `VolumeGrid-<tag>.zip` 上传到新的 GitHub Release，同时保留 workflow artifact 方便调试

## 运行方式

- 双击 `.app`，或使用 `open build/Build/Products/Release/VolumeGrid.app`
- 在 Xcode 中选择 `Product > Run`（快捷键 `⌘R`），可以直接调试运行


## Description

Brings back the classic volume HUD style on macOS Tohoe 26 and more.

Naive, Lightweight, and Minimalistic volume HUD replacement for macOS Tohoe 26+.

Suit for users who frequently adjust volume and have multi-monitor setups.
