# DrinkTrack 图标与开屏图 — 给设计替换用

这里放的是**占位图**，不是最终设计。Simmons 做好 Logo / 开屏图后，按下面的文件名和尺寸直接覆盖即可，不需要改工程结构、不需要改代码。

占位图是纯色底加一只简单的杯形线条，方便现在打包安装；请整张替换，不要在占位图上修修补补。

## 1. App 图标（主屏幕 / App Store）

替换这个文件，**保持文件名不变**：

```
DrinkTrack/DrinkTrack/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

要求：

- 正好 **1024 × 1024** 的 PNG
- **不要透明通道**（App Store 会拒）
- **不要**自己画圆角或刘海遮罩，系统会统一裁切
- `Contents.json` 已经指向 `AppIcon.png`，换图即可

如果以后要做深色或着色图标，再在同一个 `AppIcon.appiconset` 里补文件，并在 `Contents.json` 中增加对应条目，例如：

```json
{
  "filename" : "AppIcon-dark.png",
  "idiom" : "universal",
  "platform" : "ios",
  "size" : "1024x1024",
  "appearances" : [{ "appearance" : "luminosity", "value" : "dark" }]
}
```

现在不必做。

## 2. 开屏 Logo

开屏背景色来自 `LaunchBackground.colorset`（当前是 `#256ABF`，和占位图标同色）。Logo 叠在正中央。

替换这三张，**保持文件名不变**：

```
DrinkTrack/DrinkTrack/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png       256 × 256  (@1x)
DrinkTrack/DrinkTrack/Assets.xcassets/LaunchLogo.imageset/LaunchLogo@2x.png    512 × 512  (@2x)
DrinkTrack/DrinkTrack/Assets.xcassets/LaunchLogo.imageset/LaunchLogo@3x.png    768 × 768  (@3x)
```

建议：

- PNG，**可以带透明**，好叠在开屏背景上
- 内容居中；可以是纯 Logo，也可以是 Logo + 名称（占位图带了 DrinkTrack 字样）
- 三张应是同一构图的不同分辨率，不要只换其中一张

如果只先交出一张高清图，请至少提供 768 × 768（@3x），另外两张按比例缩小。

## 3. 开屏背景色 / 强调色（可选）

- 开屏背景：`LaunchBackground.colorset/Contents.json`（现在是 `#256ABF`）
- 按钮和系统强调色：`AccentColor.colorset/Contents.json`（现在同样是 `#256ABF`）

改颜色时只动 `components` 里的 RGB，不要改 `colorset` 的名字。`Info.plist` 的 `UILaunchScreen` 已经引用了 `LaunchBackground` 和 `LaunchLogo`。

## 4. 不要改的东西

- 不要重命名 `AppIcon`、`LaunchLogo`、`LaunchBackground` 这些资源集
- 不要删 `Contents.json`
- 不需要新增 Launch Screen Storyboard，也不需要改 Xcode 工程文件

替换后重新编译即可在模拟器和真机上看到新图。
