# 访达角标诊断

## v0.5.0 更新

用户选择仅保留原生角标，新增“检查角标”“重载扩展”。重载只针对 com.mackit.app.finder，停止旧实例后再恢复。正常退出主动取消角标、清空 directoryURLs、停止监听并退出扩展实例，下次启动自动恢复由本应用暂停的启用状态；不修改其他扩展。主程序退出和恢复流程已在本机验证。

诊断区分未启用、未收到状态回执、已同步但未收到角标请求、已收到请求。系统同目录扩展竞争无法通过公开优先级设置彻底解决，用户未授权永久停用其他扩展，不实施修改文件自定义图标或注入访达的替代方案。


v0.4.0：角标更新为无底橙色剪刀；下文为历史排查记录。应用卸载功能及其参考实现已移除。

## 2026-10-28 实测

- 主程序与扩展使用相同 Personal Team 签名和共享容器。
- 0.2 仅依赖分布式通知，缺少同步回执。0.3 增加目录级文件事件监听（兼容原子写替换）、初始化时明确注册 directoryURLs、按访达回调设置首次角标、已显示项目的按需更新及回执。
- 用户现场测试曾出现：扩展已同步一个待移动项目，但访达没有请求角标。
- 经用户明确允许，临时关闭 BetterTouchTool、ArcZip、vivo 的 Finder Sync 扩展，仅保留 MacKit；用户确认角标出现。
- 随后按约定恢复三项扩展；用户反馈恢复后似乎也不冲突，要求先不继续排查。当前全部维持原启用状态。不能把隔离时成功认定为某个扩展必然冲突；此次重载和初始化修复也可能参与了恢复。
- 用户进一步指定角标改为剪刀，已将橙色箭头改成橙色圆底白色剪刀。

## 系统限制

Apple DTS 说明，同一目录只能由一个 Finder Sync 扩展控制，外层目录扩展还可能影响子目录；/Applications 等部分目录不支持。不能承诺与所有右键/云盘扩展同时显示角标。不要通过覆盖用户文件自定义图标或注入 Finder 绕过限制。

[Apple 技术说明](https://developer.apple.com/forums/thread/756711)
[目录初始化规则](https://developer.apple.com/documentation/findersync/fifindersynccontroller/directoryurls)
[首次角标回调规则](https://developer.apple.com/documentation/findersync/fifindersynccontroller/setbadgeidentifier(_:for:))

## 排查

1. 在普通本地文件夹选文件按 ⌘X；避开应用程序目录及云盘。
2. 看“待移动角标”状态：等待扩展同步表示通信未完成；已同步但等待请求表示访达尚未请求角标；已响应表示回调已发生。
3. 如需排除其他扩展冲突，由用户确认后临时停用相关访达扩展，再重新打开测试文件夹。
4. 测完恢复原状态；永久关闭必须按用户选择处理。

## 卸载扫描参考

本轮阅读了 Vorssaint 的 AppUninstaller.swift 与 UninstallerSupport.swift，参考其应用身份与已知目录扫描思路，独立实现。扫描从 LaunchAgents/LaunchDaemons 配置及应用内嵌 LoginItems 识别关联项，不调用 sfltool，不读写私有后台任务数据库。不能据此判断每个系统登录项当前启用状态，界面提供系统设置入口。

[参考源码](https://github.com/vorssaint/vorssaint-utils/tree/main/Sources/Vorssaint/Services/Uninstall)

最终重载验收：通过界面点击重载后，旧扩展 PID 已消失，只剩新的扩展实例；签名校验成功。对系统暂停后无法处理停止通知的实例，使用当前用户 UID 与本应用内精确可执行路径双重匹配后发送 SIGTERM，不按名称匹配、不结束访达或其他扩展。
