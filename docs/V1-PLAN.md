> 历史规划：v0.4.0 已按用户要求彻底移除应用卸载功能；当前实现以 README 与 STATUS.md 为准。

# MacKit 首版开发方案

日期：2026-10-28。状态：规划完成，关键系统行为待原型验证；本文不代表功能已经实现或性能已经测得。

## 1. 产品定位与已确认范围

做一个原生、低常驻开销、按需工作的 macOS 工具集。首版只包含清洁模式、Finder 剪切、应用卸载，以及支撑它们的设置、权限管理和启动入口。

| 项目 | 决策 |
| --- | --- |
| 技术 | Swift 6、SwiftUI，系统集成使用 AppKit 和 Apple 框架 |
| 扩展方式 | 编译期功能模块，各自可启停；首版不做第三方动态插件平台 |
| 常驻形态 | 主程序后台运行，无 Dock 图标、无菜单栏图标 |
| 自启动 | 支持用户登录后启动；不是登录前的系统服务 |
| Finder 视觉反馈 | 用户已接受“待移动”角标，不要求 Windows 式整枚图标半透明 |
| 清洁输入 | 键盘与触控板同时锁定；用户已明确补充触控板要求 |
| 额外功能 | 仅列为候选，获得用户明确同意后才加入范围 |

用户确认支持范围为 macOS 14–27，重点支持 26、27；当前开发机为 macOS 26.6.2，Xcode 27.1 / macOS 27 SDK。最低部署版本固定为 14.0，使用 Observation。开发及首轮实机验证优先 Apple Silicon；14、15、27 和 Intel 的运行兼容性须由对应系统/硬件验证，使用 27 SDK 编译不等于在 27 上实测通过。

## 2. 启动与日常入口

首次从 Finder 或 Spotlight 打开应用时显示设置窗口：三个功能入口、功能开关、快捷键、自启动、权限状态和“退出 MacKit”。后续再次打开同一个应用，唤起已有窗口，不启动第二个实例。

窗口关闭后后台继续运行。登录自启动时不弹出窗口；快捷键唤起控制窗口。初始快捷键建议 ⌃⌥⌘M，清洁模式建议 ⌃⌥⌘K，均可修改并检测注册冲突，最终默认值以实机冲突检查为准。即使没有快捷键或辅助功能权限，也能通过再次打开应用进入设置。

主程序设置 `LSUIElement = true`，不创建 `NSStatusItem` / `MenuBarExtra`。通过 `NSApplicationDelegate` 管理重新打开、激活窗口、登录启动和退出。登录启动使用 `SMAppService.mainApp`，界面如实显示 enabled、requiresApproval、未注册等状态，不把调用注册成功等同于一定已经启用。[Apple：LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)、[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)。

## 3. 清洁模式

### 用户流程

1. 点击“开始清洁”或使用快捷键；检查权限与输入拦截器是否可用。
2. 显示短倒计时和提示：“键盘与触控板将锁定，连续按 5 次 Esc 退出。”倒计时期间可以取消。
3. 拦截器成功安装后进入清洁状态，内建显示器显示纯黑覆盖层。初始提示淡出，按 Esc 时临时显示解锁进度，便于擦拭屏幕。
4. 五次独立的 Esc 按下并释放后退出，移除覆盖层、恢复指针、注销输入拦截，恢复其他模块。

黑屏指黑色画面，不承诺关闭背光、断开显示器或令系统睡眠。首版不使用私有亮度接口；这样退出时不需要恢复系统亮度。通过 `CGDisplayIsBuiltin` 识别内建显示器，不能把当前主显示器等同于内建显示器。[Apple：CGDisplayIsBuiltin](https://developer.apple.com/documentation/coregraphics/cgdisplayisbuiltin%28_%3A%29)

扩展显示模式下默认只覆盖内建屏；外接屏显示必要的锁定提示。镜像模式、合盖、无内建显示器时，须明确提示显示器策略，不能承诺镜像屏可以彼此独立变黑。无可用内建屏时，允许用户在进入前明确选择当前屏幕。

### 输入与异常恢复

- 使用可过滤事件的 `CGEventTap`，在单独的 RunLoop 线程处理；回调只做快速状态判断，不访问磁盘、不发送 Apple Events、不等待主线程。
- 拦截普通键盘按下/释放、修饰键，以及指针移动、所有鼠标按键、拖拽和滚轮事件；触控板轻点、按压、双击、右键、滚动和拖拽都纳入验收。
- 清洁期间暂停 Finder 快捷键逻辑，避免擦拭时触发文件操作。进入前等待启动快捷键的按键释放，退出时处理 Esc 释放事件，避免透传和按键状态残留。
- 正常退出需要连续 5 次独立 Esc；长按自动重复只算一次。建议相邻两次间隔不超过 3 秒，其他键或修饰键打断计数。计数窗口属于可调整的交互参数。
- 系统多指手势（Mission Control、切换桌面、显示桌面、缩放、旋转）、Force Click、媒体键需要单独验证，不能依据鼠标事件被拦截就判定成功。公开事件接口并不等于硬件禁用；Touch ID、电源长按、部分系统保留路径不承诺可拦截。
- 基于通用事件流的方案通常也影响外接键盘、鼠标和触控板，首版应明确告知；不承诺只锁内建设备。
- 失去权限、事件 tap 无法恢复、会话切换、睡眠等异常时退出清洁并恢复输入；唤醒后不自动重锁。进程退出时依赖事件 tap 销毁恢复输入，同时验证覆盖层及指针状态。
- 仅在清洁会话内启用短周期健康检查，检查 tap 和 UI 响应。正常五次 Esc 解锁与异常恢复属于不同路径，不承诺阻止系统紧急退出。

Apple 文档确认事件 tap 可观察/改变事件流，并可能因不响应而被禁用；因此必须把异常恢复作为核心逻辑。[Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services)、[tapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable%28tap%3Aenable%3A%29)。应用内手势事件文档不构成系统级手势可拦截的保证。[Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)。

**发布门槛：** 键盘、触控板常见操作和系统多指手势的实机结果必须记录。若核心手势仍穿透，先解决或向用户提交明确兼容性限制；不能自行把“触控板锁定”缩减为“禁用点击”后宣布完成。

## 4. Finder 剪切

### 行为契约

| 操作/场景 | 预期行为 |
| --- | --- |
| Finder 文件选择状态按 ⌘X | 建立待移动会话；源文件仍在原处，显示角标和一次简短提示 |
| 另一文件夹按 ⌘V | 仅当会话与剪贴板仍匹配时，交由 Finder 执行移动 |
| ⌘C 后 ⌘V | 保持系统复制行为 |
| Finder 重命名、搜索、路径输入 | 保持文本剪切/粘贴行为 |
| 非 Finder 应用 | 不重映射快捷键；粘贴行为由目标应用处理 |
| 再次剪切另一批文件 | 原标记清除，只保留新的一批 |
| 剪贴板被任意应用改写 | 待移动状态失效，后续 ⌘V 不再触发移动 |
| Finder 文件区按 Esc | 取消待移动标记，不删除文件；输入框和对话框中的 Esc 保持原意 |
| Finder / MacKit 重启、模块关闭 | 会话作废，清理角标，不自动续做移动 |

不修改文件隐藏属性、原始图标、扩展属性或权限来模拟剪切效果。

### 实现路线

macOS 原生支持“复制后按 ⌥⌘V 将文件移动到当前位置”。优先复用此行为，避免首版自建文件复制、跨卷删除和覆盖冲突引擎。[Apple：Mac keyboard shortcuts](https://support.apple.com/en-us/102650)。

1. 只在 Finder 前台且焦点已确认为文件浏览区域时处理 ⌘X / ⌘V；利用 AX 焦点与应用切换事件维护状态。焦点未知或辅助功能查询失败时保留系统行为。支持桌面文件选择，排除文本编辑和模态对话框。
2. ⌘X 优先触发 Finder 原生复制，异步、限时等待文件 URL 与剪贴板版本更新；只有确认得到此次操作的文件列表才建立 `CutSession`。延迟期间重验前台 PID、焦点和剪贴板，避免把其他应用复制的内容认领为本次剪切。
3. `CutSession` 保存会话 ID、源 URL、可用的资源标识、剪贴板 changeCount/文件列表摘要、创建时间与状态。⌘V 前再次核对，过期或不匹配则取消。
4. 在有效文件目标上下文，将这一组 ⌘V 事件转换成 Finder 的 ⌥⌘V；正确匹配按下/释放、修饰键和合成事件标记，防止递归和重复触发。第一次提交后立刻进入 handoff 状态，避免快速连按重复移动。
5. Finder 负责冲突对话框、传输、跨卷行为及原生撤销。我们只显示“已交给 Finder”，不能在发送快捷键后自行宣布“移动成功”。提交后清除待移动状态；若用户在 Finder 取消，再次 ⌘X 即可重试。

**必须验证的取舍：** 原生快捷键调用没有通用、可靠的事务完成回调，因此首版不提供自有传输进度、自动重试或移动完成通知。跨卷取消、云文件、断网、权限失败和 ⌘Z 是否符合预期都属于集成验证，不凭推测保证。首版不静默切换为自定义文件移动器。

如原生复制路线无法稳定读取选中文件，原型阶段评估用 Finder Apple Events 获取选择，届时才增加“自动化 → Finder”权限；避免在默认路线预先要求额外权限。不要依赖 `FIFinderSyncController.selectedItemURLs()` 作为任意时刻的全局选择查询，它有扩展调用上下文限制。

### 角标扩展

增加 `MacKitFinderExtension`，通过 Finder Sync 为当前待移动文件设置“待移动”角标。用户需要在系统设置启用扩展；未启用时显示清楚的启用提示和临时状态提示，基础剪切操作可继续，但不声称角标已经生效。

主程序和扩展通过 App Group 共享小型、带版本号的状态快照；通知只用作提示重新读取，避免高频轮询。只注册当前待移动源目录所需的观察范围，结束后移除。验证新注册目录的角标刷新、Finder 重启、多扩展实例和崩溃后的旧角标清除；使用会话有效性检查和有界过期机制，避免永久残留。

待移动期间可用低频、限时的剪贴板版本检查清理角标；无待移动会话时没有剪贴板轮询。不读取、保存或上传普通剪贴板正文。

Apple 文档公开的能力是监控目录、角标和相关菜单，不包含任意修改 Finder 图标透明度。这里的设计判断基于这些公开能力，不代表采用私有注入可以成为稳定产品方案。[Finder Sync 指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)。

云盘 File Provider 路径和其他角标扩展可能冲突，须实测。发生冲突时保留移动功能并提示角标不可用，不能覆盖其他软件的文件元数据；不承诺所有目录都一定显示角标。[GitFinder 作者对 File Provider 限制的说明](https://gitfinder.com/support)。

## 5. 应用卸载

### 用户流程

选择或拖入一个 `.app` → 扫描 → 展示分类清单、大小、关联依据和未扫描范围 → 用户审阅勾选 → 请求正常退出正在运行的目标应用 → 再次校验文件 → 移到废纸篓 → 逐项报告成功、跳过或失败。

“扫描所有相关文件”是目标，不能作为完整性承诺：应用可以把数据放在任意位置，部分路径受权限保护，共享数据也不能仅凭名称归属。界面应写“发现的关联项目”，并显示扫描范围与无法访问的目录。

### 扫描规则

从 Bundle ID、应用名称、应用包内嵌套组件、签名 Team ID、可读取的 entitlements 等建立应用身份。用 `Bundle` / Property List 解析和 Security.framework 查询签名，不通过拼接用户路径执行 shell 命令。

| 范围 | 识别原则与处理 |
| --- | --- |
| 所选 `.app` 本体 | 精确用户选择；禁止系统应用及 MacKit 自身进入普通卸载流程 |
| `~/Library/Caches`、`Preferences`、`HTTPStorages`、`WebKit` | 以精确 Bundle ID、已验证命名规则为主 |
| `~/Library/Application Support`、`Logs`、`Saved Application State` | 身份证据结合路径规则；名称相似只能作为候选 |
| `~/Library/Containers` | 读取可访问的容器元数据；精确关联也要区分用户数据与缓存 |
| `~/Library/Group Containers` | entitlement 精确匹配只能证明使用关系，不能证明独占；默认不勾选 |
| 用户 LaunchAgents、应用内登录项及辅助组件 | 检查程序路径、标识和归属；运行中的服务不能只删配置文件冒充已卸载 |
| `/Library` 下关联配置、缓存、LaunchDaemons、PrivilegedHelperTools | 扫描可读位置并报告；需管理员或专用卸载器的项目首版不自动删除 |
| 用户文档、工程、云端数据、其他账户和系统目录 | 不因名称相似自动加入删除计划 |

先查已知路径和精确规则，按需扫描候选目录；Spotlight 仅作补充，索引缺失不等于没有文件。默认不递归扫描整个磁盘，不读取文件正文，不跟随符号链接扫描到范围外。扫描支持取消、部分结果和进度；大目录大小异步计算，未知大小不显示为零。

每个结果包含 `url / category / evidence / confidence / risk / size / accessStatus`。置信度与删除风险分开：精确属于该应用的数据库也可能含重要用户数据。

- 高置信且低风险的缓存、日志、状态文件可默认勾选。
- 配置项、Application Support、Containers 中的数据单独说明影响，由用户选择。
- 仅名称匹配、共享容器、同一厂商公共目录默认不勾选；无法确定归属则保留。
- Bundle ID、Team ID 都不能独立作为递归删除整个厂商目录的理由。

### 执行边界

生成固定 `RemovalPlan`，执行前重新检查目标身份、文件类型、符号链接、资源标识与路径边界；消除父子条目重复。检测到扫描后替换或身份不一致则跳过。逐项用 `FileManager.trashItem` 移到废纸篓，失败不改用永久删除或 `rm -rf`。[Apple：trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem%28at%3Aresultingitemurl%3A%29)。

首版不包含管理员常驻 helper。涉及系统扩展、驱动、特权服务或厂商卸载流程时，明确提示使用官方卸载器，并保留未处理项目。完整磁盘访问不等于管理员权限，也不能绕过系统保护。普通第三方应用是首版卸载目标。

如果应用仍运行且无法正常退出，暂停执行并提示用户；不自动强制结束进程。记录原路径、实际废纸篓路径与逐项结果，供用户查看和手动恢复。不承诺多文件事务原子回滚，也不承诺恢复所有后台服务状态。取消时保留已完成结果，不把部分成功展示成全部完成。

## 6. 技术选型与模块结构

| 层次 | 选择 | 理由 |
| --- | --- | --- |
| 工程 | Xcode app target + Finder Sync extension target；核心逻辑本地 Swift Package | 便于签名、扩展打包和纯逻辑测试 |
| 语言 | Swift 6，严格并发检查 | 模块状态隔离，控制扫描与 UI 并发 |
| UI | SwiftUI、Observation；AppKit NSPanel/NSWindow 桥接 | 设置和清单原生化，窗口控制可靠 |
| 输入 | CoreGraphics CGEventTap + ApplicationServices AX | 有条件拦截、焦点识别、权限检测 |
| 文件 | Foundation FileManager、URL resource values；必要时 NSMetadataQuery | 限定范围扫描、废纸篓、元数据 |
| 应用身份 | Bundle、Security.framework | 精确关联依据 |
| 启动 | ServiceManagement SMAppService | 系统支持的登录启动机制 |
| 配置 | UserDefaults；小型 Codable JSON 快照/操作记录 | 当前没有数据库需求 |
| 日志/性能 | OSLog、signpost、Instruments | 不需要日志/遥测第三方依赖 |
| 测试 | Swift Testing 测纯状态/规则，XCTest 做必要集成 | 文件删除和输入拦截重点验证 |
| 分发 | Developer ID 签名 + Hardened Runtime + notarization，DMG/ZIP | 适合需要全局输入和广泛文件访问的桌面工具 |

主程序按非 App Sandbox 路线设计，TCC 权限仍然生效；Finder Sync 扩展按其 sandbox、App Group 与签名要求独立配置。公证不等于 App Store 审核。首版不以 App Store 为分发目标，后续若要上架需重新评估功能与权限。[Apple：公证分发](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

建议目录：

```text
MacKit/
  App/                 # AppDelegate、窗口路由、登录启动
  UI/                  # 功能入口、设置、权限引导
  Features/
    Cleaning/          # 状态机、Esc 计数、覆盖层
    FinderCut/         # 剪切会话、原生移动委托
    Uninstaller/       # 身份解析、扫描、审阅、执行
  Platform/            # EventTap、AX、屏幕、文件系统适配器
Packages/MacKitCore/   # 协议、模型、纯规则与测试
MacKitFinderExtension/ # 角标、共享状态读取
Tests/                 # 集成测试及人工验收记录
docs/
```

`FeatureModule` 统一暴露 ID、权限依赖、状态、enable/disable；设置页面单独注册。共享 `PermissionService`、`InputCoordinator`、`WindowRouter`、`SettingsStore`。功能模块通过协议使用系统适配器，避免互相调用内部实现。清洁模式拥有最高输入优先级，退出后统一恢复已启用模块。

扫描使用 actor 与有界并发工作任务，取消显式传播；UI 更新回 MainActor。不要把同步磁盘遍历放到 MainActor，也不要假定 `Task {}` 会自动脱离主线程。低层输入回调只接触线程安全的最小快照，不能同步等待 actor 或主线程。

模块是代码组织与按需启停边界，不为每个功能建立常驻进程。首版主进程加系统按需运行的 Finder 扩展；扫描结束释放大列表和缓存，关闭窗口释放可重建 UI 资源。后续有证据表明需要隔离时，再增加按需 XPC 服务。

## 7. 权限策略

| 权限/设置 | 何时需要 | 缺失时的行为 |
| --- | --- | --- |
| 辅助功能 | 启用清洁模式/过滤键盘事件、AX 焦点检查 | 不进入伪锁定状态，解释用途并引导授权 |
| 输入监控 | 由最终 tap 类型和目标系统实际检查决定 | 按原型结果申请，不无条件要求所有权限 |
| Finder 扩展启用 | 启用角标反馈 | 提示未启用；移动逻辑与角标状态分开显示 |
| 自动化 → Finder | 仅 Apple Events 备用路线启用后 | 拒绝时禁用依赖该路线的操作，不反复弹窗 |
| 文件与文件夹/完整磁盘访问 | 扫描受保护路径时按需说明 | 基础扫描可运行，显式展示不完整结果 |
| 登录项 | 用户开启自启动 | 按系统实际注册/批准状态显示 |

不开启屏幕录制权限来实现黑色覆盖层，不要求摄像头、麦克风或网络权限。无需账号与云服务；首版不加入遥测、后台联网和自动更新模块。

## 8. 性能预算

以下是待测目标，不是当前结果。使用 Release 构建、关闭窗口、稳定空闲 5 分钟；记录硬件和系统版本，主程序与扩展分别计量，并补充总占用。

| 指标 | 初始目标 |
| --- | --- |
| 主程序空闲 CPU | 平均低于单核 0.2%，无持续周期性尖峰 |
| 主程序空闲内存 | 争取低于 60 MB physical footprint；先量基线再优化 |
| 主程序与扩展合计空闲内存 | 争取低于 90 MB；系统扩展生命周期单独记录 |
| 无任务时磁盘/网络 | 无周期扫描，无后台网络请求 |
| 清洁静态画面 | 无持续动画或显示刷新计时器 |
| 扫描并发 | 初始限制为 2 个 I/O 工作任务，测量后调整 |
| 扫描结果 | 分批流式显示，优先精确路径结果，支持及时取消 |

通过 NSWorkspace/屏幕/会话事件驱动状态，Finder 不在前台时停用不必要的剪切拦截。只在待移动会话期间检查剪贴板版本，只在清洁期间检查锁定健康。用 Instruments 检查能耗、唤醒次数、内存增长和输入回调耗时；不为追求很小的安装包牺牲恢复逻辑。

## 9. 开发顺序与验收

估算以一名熟悉 macOS 的开发者投入为基准，约 24–36 个工作日；硬件覆盖、系统差异和权限问题可能增加时间。先过原型门槛，再投入完整 UI。

| 阶段 | 工作量估算 | 交付与通过标准 |
| --- | --- | --- |
| P0 系统可行性 | 3–5 天 | 输入锁定/手势矩阵、内建屏覆盖、五次 Esc、Finder 焦点判断与原生移动、真实角标、App Group 签名、基本卸载扫描样本 |
| P1 工程基础 | 2–3 天 | 无 Dock/菜单栏图标、重复打开唤起、登录启动、模块注册、权限与设置 |
| P2 清洁模式 | 3–4 天 | 键盘与触控板、覆盖层、计数防重复、异常恢复、睡眠及多屏验收 |
| P3 Finder 剪切 | 5–7 天 | 剪切会话、角标生命周期、原生移动、复制不受影响、输入框不误伤 |
| P4 应用卸载 | 7–10 天 | 关联规则、风险清单、可取消扫描、废纸篓执行、共享文件保护、部分失败报告 |
| P5 发布验证 | 4–7 天 | 回归、性能报告、权限重授予、签名/公证、安装与自启动实测 |

P0 不通过的项目必须记录具体失败与替代路线。尤其是触控板系统手势、Finder 角标覆盖范围、原生移动行为，不能以 UI 完成代替可行性验证。

重点测试清单：

- 清洁：连续五次 Esc、长按不误解锁、擦拭混合按键、触控板所有常用操作、多指系统手势、全屏应用/Spaces、外接屏与镜像、睡眠、用户切换、撤权、tap 超时、主线程卡顿和进程被结束。
- Finder：四种视图、桌面、单选/多选、中文和非英文输入、重命名/搜索框/对话框、快速连按、其他应用改写剪贴板、同卷/跨卷、同名冲突、只读卷、网络断开、云占位文件、原生撤销、扩展关闭和重启。
- 卸载：同名不同 Bundle ID、同一应用不同副本、同厂商多个应用、共享 Group Container、符号链接、父子路径、目标扫描后替换、权限拒绝、运行中应用、取消与部分失败。用专门测试应用和临时 fixture 目录，不以用户真实数据做破坏性测试。
- 生命周期：登录静默启动、Spotlight 重开、关闭窗口继续工作、退出后释放拦截、禁用模块后停止相关工作。

自动化测试重点放在 Esc 状态机、剪切状态机、关联证据判定、删除计划边界与失败恢复。TCC、Finder 手势、多屏和实际登录行为需要实机验证，单元测试不能替代。

## 10. 参考项目与使用方式

本次已核查官方文档、仓库结构及 Vorssaint 清洁/Finder/卸载的相关实现片段；没有在本机运行这些项目，也没有把参考代码复制进本项目。

| 参考 | 用途与注意事项 |
| --- | --- |
| [Vorssaint](https://github.com/vorssaint/vorssaint-utils) | 三项功能都有对应模块，可研究状态管理和边界处理；仓库标识 GPL-3.0，直接复用前核对具体版本与许可 |
| [CleaningModeManager](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/CleaningMode/CleaningModeManager.swift) | 可参考输入拦截、会话变化、Esc 计数的设计问题 |
| [FinderCutPaste](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/Finder/FinderCutPaste.swift) | 可参考前台/焦点和剪贴板状态管理；本方案不照搬其所有操作路径 |
| [UninstallerSupport](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/Uninstall/UninstallerSupport.swift) | 可参考共享容器、身份匹配和保护范围的考虑 |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | 扫描范围与卸载交互参考；当前 [LICENSE](https://github.com/alienator88/Pearcleaner/blob/main/LICENSE.md) 为 Apache 2.0 + Commons Clause，不能按无附加限制的 Apache 项目处理 |
| [TapLock](https://github.com/ugurcandede/taplock) | 键盘/触控板事件拦截参考；README 的功能说明不是本项目的兼容性验证结果 |
| [CleanMyMac](https://cleanmymac.com/) | 产品交互参考；未核实桌面产品本体存在可复用的公开完整源码。公开的 [CleanMyMac CLI](https://github.com/MacPaw/cleanmymac-cli) 是另一项目，不应混同 |

“MacCleaner”存在多个同名项目，暂不指定某个仓库就是用户所指项目。可在后续提供准确链接后进一步比较。实现优先基于公开 Apple API 独立编写；若决定复制第三方代码，先确定产品许可与发布方式，再逐项核对许可证。

## 11. 候选功能：尚未批准、不得实现

| 候选 | 使用场景 | 预计常驻成本 |
| --- | --- | --- |
| 临时保持唤醒 | 下载、演示时在指定时间内阻止空闲睡眠 | 低，仅开启期间持有系统 assertion |
| 复制文件完整路径 | Finder 中快速取得路径供开发或分享 | 低，复用 Finder 集成 |
| 在当前目录打开终端 | 从 Finder 跳到当前文件夹的终端 | 低，按需触发 |
| 应用重置 | 保留应用本体，审阅后清除其配置/缓存 | 低，复用扫描；需额外定义用户数据保护规则 |

这些只是方向建议。首版不加入磁盘大扫除、系统监控、剪贴板历史或其他新模块；新增必须经用户同意。
