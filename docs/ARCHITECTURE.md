# MacKit 架构与目录约定

沿用 SwiftUI + Observable 状态驱动架构。AppModel 组装服务并协调功能，Service 管理系统操作与生命周期，复杂页面使用 ViewModel。简单页面不强制增加 ViewModel。

## 应用目录

- App：应用入口、生命周期、导航及功能组装。
- Features/Cleaning、FinderCut、WindowTools、Wallpaper：各业务的界面、状态及系统服务。
- Features/NotchAndLockScreen：刘海、锁屏及共用媒体等业务实现；Integration 连接应用生命周期，Settings 放置设置页面。
- Platform：跨业务共用的 macOS 能力。
- UI：主窗口、设计系统、公共控件；Pages 放置应用级设置、权限、关于页面。
- Packages/MacKitCore：按业务域组织的核心规则和状态计算。
- Extensions/Wallpaper：独立壁纸扩展的播放、渲染、XPC 和生命周期。
- Config：工程模板、权限声明、构建设置；Local.xcconfig 为不提交的本地签名配置。
- scripts：工程生成、格式检查、构建和打包。
- docs：架构约定及迁移记录。
- LICENSES：第三方许可。build、dist 为生成产物。

## 刘海运行时

NotchAndLockScreen 内的源码按业务归类，资源集中在 MacKit/Resources：

```text
NotchAndLockScreen/
├── Integration/       # 生命周期、菜单、宿主设置入口
├── Notch/             # 刘海布局、形状、状态及交互
├── Media/             # 媒体控制、歌词、封面及音频路由
├── LockScreen/        # 锁屏组件、窗口、天气及布局编辑
├── Calendar/          # 日程模型、服务及提醒活动
├── Shelf/             # 文件托盘，保留已有内部模型、视图和服务分组
├── SystemControls/    # 音量、亮度、键盘、HUD、外部显示器
├── Battery/           # 电池状态及活动
├── Privacy/           # 摄像头、麦克风、录制及隐私指示
├── Focus/             # 专注状态及活动
├── Terminal/          # 终端服务及原生视图适配
├── Activities/        # 共用实时活动容器和指示组件
└── Shared/            # 运行时配置、字符串及日志
    ├── UI/            # 跨业务展示组件与界面适配
    └── Platform/      # 共用系统接口与权限操作
```

## 依赖与界面边界

应用协调层依赖功能服务；功能依赖核心规则和公共平台能力；核心逻辑不反向依赖应用和界面。跨功能动作由应用或集成层连接，避免服务相互持有。长期保存的闭包按需弱引用，观察者、任务及系统监听随生命周期清理。

当前是 SwiftUI + AppKit，没有 UIKit 层。业务专用 NSHostingView / NSViewRepresentable 留在业务内；跨业务适配进入 UI 或 Shared/UI。小业务不强制建立 Models/Views/Services 多级目录。

文件只导入实际使用的框架。目录不是 Swift 模块。当前主程序直接编译 MacKitCore 源码，壁纸扩展直接编译其中的路由与遮挡计算；不要同时引入包依赖而重复编译。若以后真正模块化，先设计 public API，再移除 target 中重复源码，最后添加 import MacKitCore。此次目录迁移不等于完成模块解耦，运行时仍依赖部分宿主类型。

## 命名

文件名优先与主要类型一致；类型使用 UpperCamelCase，属性、方法及枚举成员使用 lowerCamelCase。界面使用业务名 + View，设置页面使用业务名 + SettingsView，页面状态使用 ViewModel，系统操作使用 Service，窗口管理使用 Controller，规则使用 Policy / Routing / Geometry。布尔值使用 is / has / can / should。组合文件按业务命名，如 NotchActivitySettings.swift。

## 迁移与验证

source-migration.json 记录本次 170 个运行时 Swift 文件的原路径与新路径。移动保留内容与许可头，原空目录移除；设置类型重命名同步宿主路由。

全部 Swift 源码由工程生成器递归收集，资源由 MacKit/Resources 递归收集并平铺到应用资源目录；禁止重复文件名。移动文件后运行 scripts/generate_project.sh，避免手改生成工程。显式共享源码路径、资源查找及构建脚本引用需另行检查。

运行 scripts/format.sh --check、git diff --check、scripts/build.sh Debug --signed。签名失败不能自动退回 unsigned。人工回归涵盖导航、权限、快捷键、窗口、媒体、文件托盘、锁屏及壁纸。

## 资源与第三方文件

MacKit/Resources/Audio 存放 Cut.wav、lock.mp3、unlock.mp3、dynamic.m4a；Animations 存放 Lock.json；Localization 存放 Localizable.xcstrings；MediaRemote 存放媒体桥接脚本。Xcode 将这些文件平铺复制到应用资源目录，现有 Bundle 和 Lottie 按名加载仍然有效，生成器检查文件名冲突。

MacKit/Assets.xcassets 是唯一的应用资源目录，包含图标、桌面预览、LocalSend 等实际使用的图片。Vendor/MediaRemoteAdapter.framework 是第三方二进制，构建时复制和签名；其许可证保持在 LICENSES。

Extensions/Wallpaper 按 Playback、Library、Snapshots、Settings、Integration、Occlusion 分组。扩展入口、Info.plist、桥接头及日志定义保留在扩展根目录。

已删除无调用方的 visualizer.metal、旧 Atoll 土耳其语应用信息文件、七组未使用展示图片，以及旧自定义空闲动画模型和未使用的偏好键声明。未删除用户磁盘上的历史偏好值。

Lock.json 被 LockIconLottieView 加载；lock.mp3 和 unlock.mp3 被锁屏音效播放器加载；dynamic.m4a 被运行时提示音调用。它们均是有效资源。

发布前复查进一步移除了无调用方的旧菜单、升级提示页、AppleScriptHelper、SystemVolumeManager、ListItemPopover、AppIcons 包装类型，以及仅由旧菜单引用的 Github/logo 图片。保留实际使用的应用图标读取函数。
