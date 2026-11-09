<div align="center">
  <img src="Assets/MacKit-Icon.png" width="112" alt="MacKit 图标">
  <h1>MacKit</h1>
  <p>轻一点，顺手一点。一个使用 Swift 与 SwiftUI 构建的原生 macOS 工具集。</p>
</div>

## 功能

### 清洁模式

擦拭设备时，临时阻止键盘、功能键、鼠标和触控板输入。

- 连续按下并松开 `Esc` 五次退出，长按不计为多次。
- 系统休眠、会话失活或显示器配置变化时自动退出。

### 访达剪切

在访达中使用熟悉的快捷键移动文件。

- `⌘ X` 标记剪切，`⌘ V` 执行移动，`Esc` 取消剪切。
- 可选剪切音效；关闭剪切功能后，音效选项随之禁用。

### 窗口预览

使用更直观的窗口预览，快速找到目标窗口。

- `⌘ Tab` 预览并切换窗口，``⌘ ` `` 切换同一应用内的窗口。
- 支持普通、最小化、全屏窗口，以及同一应用的多个窗口。
- 使用方向键、Tab 或指针悬停选择，通过 `⌘ Q`、`⌘ W`、`⌘ M` 或预览按钮退出、关闭及最小化。
- 预览和操作按钮可分别控制；系统重要应用受退出保护，`⌘ ⇧ Q` 可在确认后请求退出所有可退出的应用。

#### 程序坞增强

- 悬停应用图标查看窗口缩略图，点击预览切换到目标窗口，包括最小化及全屏窗口。
- 点击当前应用图标最小化窗口，再次点击恢复。
- 悬停预览与点击最小化可分别开关。

#### 调度中心增强

- 在系统调度中心中，`⌘ Q` 请求退出鼠标悬停窗口所属的应用，`⌘ W` 关闭该窗口。
- 独立开关，按真实窗口 ID 定位目标，支持带正常窗口的后台型应用。
- 使用应用原生关闭与退出流程；未保存内容仍由对应应用处理。

### 动态壁纸

将本地视频导入系统墙纸管线，用作动态桌面、锁屏及屏幕保护素材。

- 在 MacKit 中导入视频、查看缩略图和名称、删除素材，或在访达中打开保存位置。
- 在系统墙纸设置中选择已导入视频，支持随机播放、壁纸过渡和锁屏素材选择。
- 桌面被遮挡时可暂停播放，遮挡检测间隔可调，兼顾响应速度与系统占用。
- 导入会创建独立素材副本，原文件与素材库分别管理。

### 灵动刘海

将媒体、日程、文件和终端集中在屏幕顶部，悬停展开即可操作。

- 显示系统正在播放、专辑封面与同步歌词，支持切歌、播放暂停、手动重新加载歌词和选择输出设备。
- 查看日历事件和提前提醒；使用文件托盘暂存、拖放及分享文件，在交互式终端中执行命令。
- 显示相机、麦克风、录屏、大写锁定和专注模式指示，以及蓝牙、电池、音量、亮度和背光提示。
- 支持多显示器、独立闭合宽度、展开宽度预览与悬停延迟；暂停后的媒体保留时间可调。

### 锁屏组件

在系统锁屏上查看媒体和常用信息，固定使用 v11 自定义液态玻璃样式。

- 支持媒体、天气、电池、蓝牙设备、空气质量、日历和专注模式等组件，按设置及可用数据展示。
- 主页面提供内嵌与环形组件样式、位置预览；天气页可设置温度单位与服务提供方。
- 按内建显示器比例预览布局，在预览中上下拖动调整组件位置。

### 设置与快捷键

- 设置窗口采用系统设置式侧栏、分组面板和次级页面；前进、后退保留页面浏览位置。
- 灵动刘海按媒体控制、实时活动、系统控制、日程提醒、文件托盘和终端组织设置；锁屏组件独立管理。
- 日历列表显示日历颜色及来源；权限页显示辅助功能、日历和屏幕录制的授权状态。
- 支持登录启动、Dock 与菜单栏显示，以及打开面板、启动清洁模式的自定义快捷键。
- 关于页从左上角 MacKit 图标进入，提供版本 Release 链接及窗口内的开源许可页面。

## 系统与权限

应用最低支持 macOS 14.6；原生动态壁纸扩展需要 macOS 26 或更新版本。部分效果与系统硬件、权限和系统接口可用性有关。

在权限管理页按需开启辅助功能和屏幕录制权限。日历默认关闭，启用后再申请日历权限；天气使用系统定位。

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
│   ├── Atoll/                   刘海生命周期集成与日历权限状态
│   ├── NotchRuntime/            整合后的刘海、媒体、终端和锁屏源码与资源
│   ├── Cleaning/                清洁模式
│   ├── FinderCut/               访达剪切
│   ├── Wallpaper/               本地视频管理与设置
│   └── WindowTools/             窗口预览、程序坞与调度中心增强
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

刘海与锁屏功能包含 [Atoll](https://github.com/Ebullioscopic/Atoll) 的改编代码；窗口切换和程序坞实现参考改编了 [Vorssaint](https://github.com/vorssaint/vorssaint-utils)；调度中心增强参考改编了 [CloseUp](https://github.com/oomol-lab/CloseUp)；墙纸扩展包含 [Phosphene](https://github.com/kageroumado/phosphene) 的 MIT 授权代码。具体使用范围、版本及修改说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，完整许可保留在 [LICENSES](LICENSES/)，原始版权、NOTICE、商标与修改说明集中在第三方声明中，均随应用分发。

## 参与贡献

反馈与贡献约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。
