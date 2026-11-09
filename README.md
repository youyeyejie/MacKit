# MacKit

轻一点，顺手一点。一个使用 Swift 与 SwiftUI 构建的原生 macOS 工具集。

## 功能

- **灵动刘海**：系统正在播放、同步歌词、日历、文件托盘和交互式终端；支持多显示器、独立闭合宽度及悬停展开。
- **媒体控制**：播放暂停、切歌、按应用调节音量和选择输出设备；暂停后的媒体保留时间可调，歌词优先显示在常驻外接灵动岛上。
- **实时活动**：相机、麦克风、屏幕录制、大写锁定与专注模式指示，以及蓝牙连接、电池、音量、亮度和键盘背光提示。
- **锁屏组件**：媒体、天气、电池、蓝牙、日历和专注模式；使用液态玻璃样式，可预览并调整垂直位置。
- **窗口切换**：⌘Tab 预览并切换窗口，⌘\` 切换应用内窗口；支持最小化和全屏窗口、方向键与指针选择，以及退出、关闭和最小化操作。
- **程序坞增强**：悬停预览应用窗口，点击预览切换；点击当前应用图标最小化，再次点击恢复。两项可分别控制。
- **动态壁纸**：导入本地视频到系统墙纸设置，管理缩略图与素材副本，设置过渡和遮挡暂停；支持锁屏素材选择。
- **访达剪切**：在访达中使用 ⌘X、⌘V 移动文件，Esc 取消剪切，可选音效。
- **清洁模式**：临时阻止键盘、功能键、鼠标和触控板输入；连续按下并松开 Esc 五次退出。
- **软件设置**：登录启动、菜单栏、外观、权限管理与功能开关。

## 系统与权限

应用最低支持 macOS 14.6；原生动态壁纸扩展需要 macOS 26 或更新版本，按应用调音需要 macOS 15 或更新版本。部分效果与系统硬件、权限和系统接口可用性有关。

在权限管理页按需开启辅助功能和屏幕录制权限。日历默认关闭，启用后再申请日历权限；天气使用系统定位。按应用调音首次使用时请求系统音频访问，音频仅在本机处理。

天气查询使用 Open-Meteo，失败时尝试 wttr.in；歌词查询会向网易云和 LRCLIB 发送当前歌曲的查询信息，不发送账号或 Cookie。导入壁纸会创建独立素材副本，删除原视频不会自动移除已导入的副本。

## 构建

需要完整 Xcode、命令行工具和 Python 3。所有构建产物保留在项目目录下。

```sh
# 重新生成工程（build.sh 也会自动执行）
./scripts/generate_project.sh

# 构建 Apple Silicon / Intel 通用签名版
./scripts/build.sh Release --signed
```

签名配置放在不纳入 Git 的 `Config/Local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

默认构建包含主应用、系统托管的墙纸扩展、所需资源和开源声明，并验证签名。测试不签名构建可使用 `--unsigned`。输出位置：

```text
build/DerivedData/Build/Products/Release/MacKit.app
```

工程生成逻辑全部包含在 `scripts/generate_project.sh` 中，其中内嵌 Python 用于处理工程结构；不再依赖独立的 `generate_project.py`。依赖版本保存在 `Config/RuntimePackages.resolved`。

## 打包

```sh
./scripts/package.sh
```

打包已有 Release 应用，不会重新编译；已有签名会保留。输出为 `dist/MacKit-<版本>-macOS.dmg` 和对应 SHA-256 文件。同名产物不会被覆盖，当前流程不包含 Apple 公证。

三个脚本均支持 `--help`。

## 项目结构

```text
MacKit/
├── App/                         应用入口与全局状态
├── Features/
│   ├── Atoll/                   刘海生命周期与设置承载
│   ├── NotchRuntime/            整合后的刘海、媒体、终端和锁屏源码与资源
│   ├── Cleaning/                清洁模式
│   ├── FinderCut/               访达剪切
│   ├── Wallpaper/               本地视频管理与设置
│   └── WindowTools/             窗口切换与程序坞增强
├── Platform/                    权限、快捷键与系统接口
├── UI/                          主设置界面和共享组件
└── Resources/                   应用资源
Extensions/Wallpaper/            系统墙纸扩展
Packages/MacKitCore/             共享功能逻辑
Config/                         构建配置、工程模板与依赖版本
LICENSES/                       仍使用组件的原始许可正文
scripts/                        工程生成、构建和打包
MacKit.xcodeproj/                自动生成的工程
build/                          本地构建产物与缓存（忽略）
dist/                           发布包（忽略）
```

版本号在 `Config/Shared.xcconfig` 中维护。`MacKitCore` 源码由生成的工程直接编译到应用中。

## 开源许可与来源

当前组合程序按 [GPL-3.0-or-later](LICENSE) 分发，MacKit 修改部分 Copyright (c) 2026 youyeyejie。

刘海与锁屏功能包含 [Atoll / boring.notch](https://github.com/Atoll-Labs/Atoll) 的改编代码；窗口切换和程序坞实现参考改编了 [Vorssaint](https://github.com/vorssaint/vorssaint-utils)；墙纸扩展包含 [Phosphene](https://github.com/kageroumado/phosphene) 的 MIT 授权代码。迁移到 MacKit 目录不改变原作者版权或许可。

具体使用范围、版本及修改说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，完整许可保留在 [LICENSES](LICENSES/)，原始版权、NOTICE、商标与修改说明集中在第三方声明中，均随应用分发。素材与商标遵循各自声明；用户导入的视频不属于项目源码许可范围。发布二进制时应同时提供与该发布版本对应的完整源码。

## 参与贡献

反馈与贡献约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。
