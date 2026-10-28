# MacKit

Swift 6 + SwiftUI 原生 macOS 工具集，支持目标为 macOS 14–27，重点支持 26、27。无 Dock 图标、无菜单栏状态图标，按需运行。

当前阶段：**0.1 开发预览**。主程序与 Finder 扩展可编译，已在 macOS 26.6.2 打开窗口；核心逻辑 12 项测试通过。真实输入拦截、Finder 移动和跨系统兼容性仍需人工验收，不能视为已发布版本。

已接入：

- 清洁模式：键盘/触控板事件拦截、内建屏黑色覆盖层、五次独立 Esc 解锁、异常恢复。
- Finder 剪切：⌘X 建立待移动会话、⌘V 委托 Finder 移动；剪贴板失效保护；独立角标扩展。
- 应用卸载：身份匹配扫描、审阅勾选、路径与文件身份复核、移到废纸篓、逐项结果。
- 后台入口：⌃⌥⌘M 唤起、⌃⌥⌘K 开始清洁、登录启动设置、权限引导。

## 开发

使用支持 Swift 6 的 Xcode。本次使用 Xcode 27.1 / macOS 27 SDK；最低部署目标始终为 14.0。无需第三方包。

```sh
scripts/build.sh Debug
scripts/test.sh
scripts/run-preview.sh
```

预览应用：`build/DerivedData/Build/Products/Debug/MacKit.app`。

Xcode 工程：`MacKit.xcodeproj`。新增 Swift 文件后执行 `python3 scripts/generate_project.py` 更新工程；生成器不读取构建目录。核心逻辑同时作为本地 Swift Package 供测试，Xcode app target 直接编译同一份核心源码。

## 签名

`build.sh` 生成未签名构建，`run-preview.sh` 做本地 ad-hoc 签名，仅用于开发预览。当前未发现有效开发签名身份。

要使用角标/App Group 并验证登录启动，在 Xcode 配置自己的开发团队，或创建不纳入 Git 的 `Config/Local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

随后在 Xcode 开启自动签名构建。主程序及扩展需使用相同团队并正确配置 `TEAMID.com.mackit.shared` App Group；如修改 Bundle ID，要同时修改工程生成器及相应注册标识。发行需 Developer ID、公证和独立的兼容性验收。

## 文档

- [手工验收步骤](docs/MANUAL-TEST.md)
- [首版开发方案](docs/V1-PLAN.md)
- [实现与验证状态](docs/STATUS.md)

用户已确认采用“待移动”角标，并要求清洁时锁定触控板。其他候选功能未加入实现。Git 按重要开发节点提交；未复制第三方项目实现代码。
