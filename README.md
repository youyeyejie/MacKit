# MacKit

Swift 6 + SwiftUI 原生 macOS 工具集，支持目标为 macOS 14–27，重点支持 26、27。默认隐藏 Dock 与菜单栏图标，可在软件设置分别开启，按需运行。

当前阶段：**0.3 开发预览**。主程序与 Finder 扩展已用 Personal Team 开发证书签名并安装，核心逻辑 20 项测试通过。用户已验证首版基本功能；新版交互和跨系统兼容性继续人工验收。

已接入：

- 清洁模式：立即锁定键盘/触控板、内建屏黑色覆盖层、常驻五圆点提示、五次独立 Esc 解锁、异常恢复。
- 访达剪切：⌘X 建立待移动会话、⌘V 委托 Finder 移动；剪贴板失效保护；独立角标扩展。
- 应用卸载：嵌套目录/容器/隐藏配置扫描、可补充扫描位置、启动项与权限清单、逐项审阅、身份复核、移到废纸篓及操作记录。
- 后台入口：默认 ⌃⌥⌘M 唤起、⌃⌥⌘K 开始清洁，支持录制与保存新快捷键；登录启动、显示位置设置和自动权限状态。

## 开发

使用支持 Swift 6 的 Xcode。本次使用 Xcode 27.1 / macOS 27 SDK；最低部署目标始终为 14.0。无需第三方包。

```sh
scripts/build.sh Debug
scripts/test.sh
scripts/run-preview.sh
```

预览应用：`build/DerivedData/Build/Products/Debug/MacKit.app`。

Xcode 工程：`MacKit.xcodeproj`。新增 Swift 文件后执行 `python3 scripts/generate_project.py` 更新工程；生成器不读取构建目录。核心逻辑同时作为本地 Swift Package 供测试，Xcode app target 直接编译同一份核心源码。

## 本机签名与安装

已在本机验证：Apple ID 的 Personal Team 创建 Apple Development 证书后，可以签名当前 macOS 主程序及 Finder 扩展。仅自己使用的当前流程无需先购买付费会员；这不等同于获得 Developer ID 发行、公证权限。`run-preview.sh` 优先打开已安装的签名版本。

要使用角标/App Group 并验证登录启动，在 Xcode 配置自己的开发团队，或创建不纳入 Git 的 `Config/Local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

在 Xcode「Settings → Accounts → Manage Certificates」创建 Apple Development 证书，然后：

```sh
scripts/build.sh Debug --signed
scripts/install-local.sh Debug
scripts/run-preview.sh
```

安装位置：`~/Applications/MacKit.app`。已有安装会备份到 `build/Backups`。主程序及扩展使用同一团队和 `TEAMID.com.mackit.shared` 共享容器。安装后在系统设置启用 Finder 扩展；签名改变可能需要重新添加辅助功能授权。本机团队配置、私钥、证书不纳入 Git。

无证书时可运行 `scripts/build.sh Debug --unsigned`，仅用于构建检查，不能据此验证角标共享容器。发行需要另行配置发行签名、公证和兼容性验收。

## 文档

- [手工验收步骤](docs/MANUAL-TEST.md)
- [首版开发方案](docs/V1-PLAN.md)
- [实现与验证状态](docs/STATUS.md)
- [应用图标与生成提示](docs/ICON-DESIGN.md)

用户已在关闭其他访达扩展的隔离环境中确认角标显示正常。macOS 对同目录 Finder Sync 扩展存在竞争限制；若其他扩展占用，需在系统设置取舍。参见 [角标诊断](docs/BADGE-DIAGNOSTICS.md)。

用户已确认采用“待移动”角标，并要求清洁时锁定触控板。其他候选功能未加入实现。Git 按重要开发节点提交；未复制第三方项目实现代码。
