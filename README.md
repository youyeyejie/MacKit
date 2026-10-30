<div align="center">
  <img src="Assets/MacKit-Icon.png" width="112" alt="MacKit 图标">
  <h1>MacKit</h1>
  <p>轻一点，顺手一点。一个使用 Swift 与 SwiftUI 构建的原生 macOS 工具集，后台占用约 50 MB。</p>
  <p>macOS 14+ · Apple Silicon / Intel · 无第三方运行时依赖</p>
</div>

## 功能

### 清洁模式

擦拭屏幕、键盘和触控板时，临时拦截键盘、鼠标及触控板输入。

- 内建显示器显示黑色清洁遮罩，其他屏幕显示退出提示。
- 没有内建显示器时，可选择使用当前屏幕。
- 连续按下并松开 **Esc 5 次**退出；相邻两次间隔不超过 3 秒，长按不计为多次。
- 系统休眠、会话失活、显示器配置变化或输入监听中断时，自动退出清洁模式。

### 访达剪切

在访达的文件浏览区域，使用熟悉的快捷键移动文件。

| 快捷键 | 操作 |
| --- | --- |
| `⌘ X` | 将选中的文件标记为待移动 |
| `⌘ V` | 将待移动文件交给访达执行移动 |
| `Esc` | 取消待移动状态 |

在「访达剪切」页面开启功能，可单独开关剪切音效。文件移动、重名冲突及撤销由访达处理。剪贴板内容变化后，待移动状态会失效；取消访达的移动操作后，需要重新按 `⌘ X`。

### 窗口切换

通过窗口预览快速选择目标窗口，支持最小化、全屏窗口及同一应用的多个窗口。

- `⌘ Tab` 切换窗口，``⌘ ` `` 切换应用内窗口，松开 `⌘` 确认选择。
- 使用方向键或指针悬停选择窗口，窗口较多时自动换行显示。
- 可单独开启预览操作按钮及 `⌘ Q`、`⌘ W`、`⌘ M` 快捷键；Finder 等系统组件受退出保护。`⌘ ⇧ Q` 可在确认后请求退出所有可退出的应用。
- 最小化窗口排在普通窗口之后；无窗口应用排在最后，选中确认后打开应用。

### 程序坞增强

- **悬停预览**：将指针停在程序坞应用图标上，查看窗口缩略图，点击预览切换到对应窗口。
- **点击图标最小化**：点击当前应用的程序坞图标最小化窗口，再次点击还原；全屏窗口则隐藏应用。
- 在预览中查看最小化和全屏状态，并直接退出应用、关闭或最小化窗口。
- 悬停预览与点击最小化可分别开关。

macOS 26 及更新系统采用 Liquid Glass 界面，较旧系统使用兼容样式。

### 软件设置

- 自定义登录自启动。
- 自定义是否在 Dock 和菜单栏显示。
- 自定义打开 MacKit、开始清洁的全局快捷键。
- 设置保存在本机，无需账号或云服务。

默认全局快捷键：

| 操作 | 快捷键 |
| --- | --- |
| 打开 MacKit | `⌃ ⌥ ⌘ M` |
| 开始清洁 | `⌃ ⌥ ⌘ K` |

## 使用

从 [Releases](https://github.com/youyeyejie/MacKit/releases) 下载构建好的应用，将 DMG 中的 `MacKit.app` 拖入 `Applications`，即可安装应用并使用。

清洁模式、访达剪切、窗口切换和程序坞增强需要**辅助功能权限**；窗口预览还需要**屏幕录制权限**。在应用的「权限管理」页面点击对应的「前往授权…」，按系统提示允许 MacKit。授权后若功能仍未生效，退出并重新打开应用。

## 开发与构建

需要 macOS、完整安装的 Xcode，以及支持 Swift 6 的工具链。三个脚本使用系统自带的 zsh 和 macOS 工具，不依赖 Python 或第三方工程生成工具。以下命令在项目根目录执行。

### 生成工程

```sh
./scripts/generate_project.sh
```

扫描应用源码、核心源码、配置和资源，生成 `MacKit.xcodeproj` 及共享的 `MacKit` Scheme。新增、删除或移动文件后，重新运行此脚本。

**生成操作会覆盖 `project.pbxproj` 和共享 Scheme。** 需要长期保留的工程配置调整，应同步修改生成脚本。

### 构建 App

```sh
# 默认：Release、开发签名、同时构建 arm64 和 x86_64
./scripts/build.sh

# Debug 构建
./scripts/build.sh Debug
```

构建脚本使用现有工程，不会自动重新生成工程。也可以用 Xcode 打开 `MacKit.xcodeproj`，选择 `MacKit` Scheme 构建和运行。

产物位置：

```text
build/DerivedData/Build/Products/Release/MacKit.app
build/DerivedData/Build/Products/Debug/MacKit.app
```

默认使用开发签名。在 `Config/Local.xcconfig` 中填写：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

然后执行：

```sh
./scripts/build.sh Release --signed
```

`Config/Local.xcconfig` 已被 Git 忽略。签名构建需要本机配置对应的开发账号及签名证书。仅需无签名构建时显式传入 `--unsigned`。

### 打包 DMG

```sh
# 打包默认位置的 Release App
./scripts/package.sh

# 打包指定 App
./scripts/package.sh /path/to/MacKit.app
```

打包脚本只处理已有 App，不会触发构建。它会在临时目录中复制应用，为无签名副本添加临时签名（ad-hoc），保留已有签名，并验证签名及 DMG 完整性。DMG 内包含指向 `Applications` 的快捷方式。

输出文件使用 App 自身的版本号：

```text
dist/MacKit-<version>-macOS.dmg
dist/MacKit-<version>-macOS.dmg.sha256
```

脚本不会覆盖同名产物；再次打包前，请先移走旧文件。当前流程不包含公证。

### 脚本帮助

三个脚本均支持 `-h`、`--help` 和 `help`：

```sh
./scripts/generate_project.sh --help
./scripts/build.sh --help
./scripts/package.sh --help
```

## 项目结构

```text
MacKit/
├── App/                       应用入口、生命周期和全局状态
├── Features/
│   ├── Cleaning/              清洁模式界面、输入过滤和服务
│   ├── FinderCut/             访达剪切界面、焦点识别和服务
│   └── WindowTools/           窗口切换、程序坞预览和窗口目录
├── Platform/                  权限、全局快捷键、事件监听和音效
├── UI/                        主界面、通用组件和样式
├── Resources/                 剪切音效
└── Assets.xcassets/            应用图标资源
Packages/MacKitCore/            功能协议、剪切会话和 Esc 退出序列
Assets/                        图标原图及 README 展示素材
Config/                        构建配置、版本号和 Info.plist
MacKit.xcodeproj/               生成的 Xcode 工程
scripts/                       工程生成、App 构建和 DMG 打包脚本
build/                         构建产物与缓存（不纳入 Git）
dist/                          DMG 和校验文件（不纳入 Git）
```

`MacKitCore` 保留 Swift Package 描述文件；当前生成的 Xcode 工程直接将其源码加入应用编译。版本号和最低系统版本在 `Config/Shared.xcconfig` 中维护。

## 参与贡献

欢迎提交问题反馈和改进建议。开发约定与 Pull Request 要求见 [贡献指南](CONTRIBUTING.md)。后续功能会根据我的使用习惯逐步添加。

## 开源协议

本项目采用 [MIT License](LICENSE)。
