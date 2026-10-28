# MacKit

Swift 6 + SwiftUI 原生 macOS 工具集，系统支持目标 macOS 14–27，重点 26、27。当前版本 **v0.8.0**。默认隐藏 Dock 和菜单栏图标，可分别开启。

## 功能

- 清洁模式：立即锁定键盘与触控板，内建屏黑屏、外接屏圆角提示，连续五次 Esc 退出。
- 访达剪切：⌘X 建立剪切状态、⌘V 委托访达移动、Esc 取消。成功剪切播放约 0.15 秒剪刀声，可关闭并保存偏好；重新开启开关时播放一次预览。
- 设置：登录后启动、显示位置、可录制或清空的全局快捷键。

v0.6.0 已完整移除剪切角标、访达扩展、共享容器与诊断重载逻辑；程序不再需要启用访达扩展。应用卸载功能也已移除。

## 开发与运行

使用支持 Swift 6 的 Xcode；当前构建环境 Xcode 27.1 / macOS 27 SDK，最低部署目标 14.0。无第三方依赖。

```sh
scripts/build.sh Debug --signed
scripts/test.sh
scripts/install-local.sh Debug
scripts/run-preview.sh
```

签名团队配置在不纳入 Git 的 `Config/Local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

本机已验证 Personal Team 的 Apple Development 签名。安装至 `~/Applications/MacKit.app`，旧版本备份在 `build/Backups`。开发签名不等于发行公证。

无证书可使用 `scripts/build.sh Debug --unsigned` 构建；稳定开发签名可减少更新后的系统授权变化。

新增 Swift 或资源文件后执行 `python3 scripts/generate_project.py` 更新单 App target 工程。核心状态机作为本地 Swift Package 测试；快捷键使用隔离配置检查。

音效从用户提供的《剪刀剪布料声-快速_爱给网_aigei_com.mp3》截取 0.085–0.235 秒，转为单声道 PCM WAV；可用 `python3 scripts/prepare_cut_sound.py /path/to/source.mp3` 重建。播放采用 NSSound，按需加载，无常驻音频引擎。

## 验证与文档

4 项核心测试与 6 项快捷键持久化检查通过。跨系统兼容性仍需实机验收。

- [手工验收](docs/MANUAL-TEST.md)
- [实现状态](docs/STATUS.md)
- [应用图标设计](docs/ICON-DESIGN.md)
