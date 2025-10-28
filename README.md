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
- [x] Linters, type checkers, auto-formatters

## 使用方法

1. 运行应用后，应用将在后台运行
2. 菜单栏会出现音量图标
3. 调节音量时会显示经典样式的弹窗
4. 点击菜单栏图标可查看当前音量和当前输出设备
5. 可设置开机自动启动

## 开发工具

本项目使用以下工具来维护代码质量和一致性：

- **SwiftLint**: Swift 代码检查工具，用于检测代码风格、潜在错误和最佳实践。
  - 安装: `brew install swiftlint`
  - 运行: `swiftlint lint`
  - 配置: `.swiftlint.yml`（自定义规则和阈值）
  - 集成: 已添加到 Xcode Build Phase，每次构建时自动检查。

- **swift-format**: Apple 官方 Swift 代码格式化工具，强调一致性和标准风格。
  - 安装: `brew install swift-format`
  - 运行: `swift-format lint --recursive .`
  - 运行: `swift-format format --recursive --in-place .`
  - 配置: `.swift-format`（JSON 格式，设置缩进为 4 空格、行长度 100 等）
  - 集成: 已添加到 Xcode Build Phase，每次构建时自动格式化。

- **SwiftFormat**: 第三方 Swift 代码格式化工具，灵活且易用。
  - 安装: `brew install swiftformat`
  - 运行: `swiftformat .`
  - 配置: 支持多种选项，可与 swift-format 结合使用。

这些工具确保代码符合项目标准，并在开发过程中自动应用。

## 运行方式

- 双击 `.app`，或使用 `open build/Build/Products/Release/VolumeGrid.app`
- 在 Xcode 中选择 `Product > Run`（快捷键 `⌘R`），可以直接调试运行
- 使用命令行构建: `xcodebuild -project VolumeGrid.xcodeproj -scheme VolumeGrid -configuration Release -derivedDataPath ~/Downloads/volumegrid-build`


## Development Tools

This project uses the following tools to maintain code quality and consistency:

- **SwiftLint**: A tool for linting Swift code, detecting style issues, potential errors, and best practices.
  - Install: `brew install swiftlint`
  - Run: `swiftlint lint`
  - Config: `.swiftlint.yml` (custom rules and thresholds)
  - Integration: Added to Xcode Build Phase, runs automatically on build.

- **swift-format**: Apple's official Swift code formatter, focusing on consistency and standard style.
  - Install: `brew install swift-format`
  - Run: `swift-format format --recursive --in-place .`
  - Config: `.swift-format` (JSON format, sets indentation to 4 spaces, line length 100, etc.)
  - Integration: Added to Xcode Build Phase, formats automatically on build.

- **SwiftFormat**: A third-party Swift code formatter, flexible and user-friendly.
  - Install: `brew install swiftformat`
  - Run: `swiftformat .`
  - Config: Supports various options, can be used alongside swift-format.

These tools ensure code adheres to project standards and are applied automatically during development.

## Description

Brings back the classic volume HUD style on macOS Tohoe 26 and more.

Naive, Lightweight, and Minimalistic volume HUD replacement for macOS Tohoe 26+.

Suit for users who frequently adjust volume and have multi-monitor setups.
