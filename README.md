<div align="center">
  <img src="Assets/MacKit-Icon.png" width="112" alt="MacKit 图标">
  <h1>MacKit</h1>
  <p>轻一点，顺手一点。一个使用 Swift 与 SwiftUI 构建的原生 macOS 工具集。</p>
  <p>macOS 14+ · Apple Silicon / Intel · 无第三方运行时依赖</p>
</div>

## 功能

### 清洁模式

一键锁定键盘和触控板，内建显示器显示黑色覆盖层，方便擦拭设备。连接外部显示器时显示圆角提示。

连续按下并松开 **5 次 Esc** 退出，每次点亮一个圆点；按其他键会清空进度，长按不会重复计数。退出提示常驻，清洁结束后恢复输入。Touch ID、电源键等系统保留操作不由应用控制。

### 访达剪切

| 快捷键 | 操作 |
| --- | --- |
| `⌘X` | 将所选文件标记为待移动 |
| `⌘V` | 移动到当前位置 |
| `Esc` | 取消剪切状态 |
| `⌘C` | 保留正常复制行为 |

文件移动、同名冲突与撤销交给访达处理。文件名编辑、搜索框等文本输入保留原有剪切粘贴行为。剪贴板被覆盖或会话过期后会取消待移动状态。

成功剪切时播放一声短剪刀音效，多选只响一次。音效可关闭，设置会保存；重新打开音效开关时播放一次预览。

**不安装访达扩展，不修改文件图标。** 当前版本不包含应用卸载功能。

### 后台与个性化

- 登录后自动启动。
- Dock 和菜单栏图标可分别开启或关闭，默认隐藏。
- 全局快捷键支持录制、冲突检查和清空，重启后保留。
- 默认 `⌃⌥⌘M` 打开主面板，`⌃⌥⌘K` 开始清洁。
- 关闭窗口后继续运行；`⌘Q` 或菜单中的退出操作结束应用。
- 无账号、无云服务，设置和功能处理留在本机。

## 下载与使用

从 [Releases](https://github.com/youyeyejie/MacKit/releases) 下载 ZIP，解压后将 `MacKit.app` 放入“应用程序”文件夹并打开。

清洁模式和访达快捷键需要 **系统设置 → 隐私与安全性 → 辅助功能** 授权。应用中的“权限管理”提供入口，返回应用后会自动更新状态。若使用不同签名重新构建，系统可能要求重新授权。

默认没有 Dock 或菜单栏图标，可通过 Spotlight、应用程序目录或全局快捷键打开主面板。

当前 v0.8.0 安装包使用 **Apple Development 开发签名，未经过 Apple 公证**，不等同于 Developer ID 发行版本。macOS 可能阻止直接打开；也可以通过下方步骤使用自己的团队构建。音效遵循系统输出音量和静音设置。

## 系统要求与验证范围

- 最低部署版本：macOS 14.0。
- 安装包：Universal，包含 arm64 与 x86_64。
- 开发与验证环境：macOS 26.6.2、Xcode 27.1、macOS 27 SDK。
- 支持目标为 macOS 14–27，重点关注 26、27；其他系统版本与 Intel 仍需实机验证。编译成功不代表所有系统交互均已验证。

## 从源码构建

需要支持 Swift 6 的 Xcode、Python 3 和系统命令行工具，无需下载第三方 Swift 包。

```sh
git clone git@github.com:youyeyejie/MacKit.git
cd MacKit
scripts/build.sh Release --unsigned
```

也可以直接使用 Xcode 打开 `MacKit.xcodeproj`。构建产物位于 `build/DerivedData/Build/Products/Release/MacKit.app`。

使用自己的 Apple 开发团队签名时，在不纳入 Git 的 `Config/Local.xcconfig` 中设置：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

在 Xcode 中准备 Apple Development 证书，再执行：

```sh
scripts/build.sh Release --signed
```

### 打包

```sh
scripts/package.sh --signed
# 无开发证书时：scripts/package.sh --unsigned
```

打包脚本输出 `dist/MacKit.app`、ZIP 和 SHA-256 校验文件；未签名构建会在打包时添加本地 ad-hoc 签名。脚本不会覆盖已有的 `dist/MacKit.app`。所有构建缓存、个人签名配置及最终二进制均不提交到源码仓库，安装包通过 Release 分发。

新增源文件或资源后，运行 `python3 scripts/generate_project.py` 更新工程。

## 项目结构

```text
MacKit/
  App/               应用生命周期、状态与入口
  Features/Cleaning/  清洁模式与输入拦截
  Features/FinderCut/ 访达剪切与会话管理
  Platform/          快捷键、权限、事件监听与音效
  UI/                页面与公共样式
  Resources/         剪切音效
Packages/MacKitCore/  共享状态机与功能接口
Config/              构建配置及 Info.plist
Assets/              图标源资源
scripts/             工程生成、构建与打包
```

## 资源说明

应用图标为项目生成资源。剪切音效来自项目作者提供的《剪刀剪布料声-快速_爱给网_aigei_com.mp3》，截取 0.085–0.235 秒，并添加极短首尾淡入淡出；保留素材来源信息，不将其声明为原创合成音效。
