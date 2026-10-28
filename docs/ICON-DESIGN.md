# MacKit 图标

使用内置 imagegen 生成，主文件：`Assets/MacKit-Icon.png`。

设计方向：深蓝玻璃圆角底座、银白折叠丝带构成抽象 M、少量青色边缘光。图形在小尺寸保留清晰轮廓，无额外文字或工具拼贴。

最终提示词：

> Use case: logo-brand. Create one polished macOS application icon for MacKit, a lightweight native Mac utility toolkit for cleaning keyboard, managing files and uninstalling apps. Square 1024x1024 app icon, transparent outer background. A generous rounded-square tile inset with correct macOS icon padding, rich midnight navy to luminous cobalt glass gradient, one bold sculptural folded silver-white M mark made from two precision-machined interlocking ribbons, subtle cyan inner light, crisp silhouette legible at 32 pixels. Premium understated Apple desktop utility feel, front-facing orthographic, clean studio highlights, subtle tactile depth. No letters or text beyond the abstract M shape, no tools collage, no Apple logo, no mockup, no extra icons, no backdrop outside the tile. One centered final production icon.

`scripts/prepare_icon.py` 用系统 sips 导出 16–1024 px 的 AppIcon 资源，保留透明通道；工程通过 Asset Catalog 编译图标。
