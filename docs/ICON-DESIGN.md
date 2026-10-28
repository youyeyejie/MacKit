# MacKit 图标（0.3）

使用内置 imagegen 生成，最终资源为 `Assets/MacKit-Icon.png`，替换 0.2 的深蓝玻璃图标。

白色圆角底座、扁平蓝色 M 和薄荷绿点缀，透明外部背景，无金属、发光或立体科技效果。`scripts/prepare_icon.py` 用系统 sips 生成 16–1024 px AppIcon 资源。应用内直接加载 AppIcon.icns，避免 NSWorkspace 返回旧版图标缓存。

最终提示词：

> Use case: logo-brand. Create a production macOS application icon for MacKit. A pure white rounded square tile with generous macOS icon inset on a genuinely transparent outer background. In its center, one very simple flat geometric M monogram, rounded friendly thick strokes in solid muted cornflower blue and a small solid mint green accent, optically balanced with generous whitespace. Modern calm everyday productivity app, approachable and clean. Strictly flat two-dimensional vector-like design, solid colors, no gradients, no glass, no metallic effects, no bevel, no glow, no perspective, no shadows, no futuristic technology aesthetic, no tools collage, no text besides the abstract M mark. Square 1024 by 1024 icon, crisp silhouette readable at 16 pixels.
