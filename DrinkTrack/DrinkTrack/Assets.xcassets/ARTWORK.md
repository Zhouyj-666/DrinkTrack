# 小酌场 / SipSession 图标与开屏图

工程名、Bundle ID 和目标名称仍是 DrinkTrack / `com.drinktrack.app`。桌面显示名（CFBundleDisplayName）和界面文案用「小酌场」，英文标识为 SipSession。

源文件保存在仓库根目录的 `artwork/`，已放进资源目录的是处理后的版本。把新图放到 `artwork/` 后，再按下面规则更新 `Assets.xcassets`，不要只改 C 盘里的原稿。

## App 图标（必须用正方形、无圆角、无透明）

路径：

```
DrinkTrack/DrinkTrack/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

要求：

- 正好 1024 × 1024 的 PNG
- RGB，不要透明通道
- 画面要铺满正方形，不要预先裁成圆角

当前文件来自 `artwork/drinktrack-logo-icon-1024.png`（Simmons 交付的正方形图标）。iOS 会自己加圆角，请不要把 `artwork/drinktrack-icon-cheers.jpg` 放到这里——那张已经带圆角，再当 App 图标会双重圆角。

`Contents.json` 和 imageset 名称不要改。

## 开屏图

开屏由 `LaunchScreen.storyboard` 全屏铺 `LaunchPortrait` / `LaunchLandscape` 图片，不再使用原来的「蓝底 + 线稿酒杯」和 `LaunchLogo`。

图片不是直接放大 720×1280 / 1280×720 的交付 JPG，而是按交付稿合成的更高分辨率版本：

- 从正方形图标里抠出圆形酒杯标志（带透明）
- 用开屏稿取样的酒红到橙色渐变铺底
- 用矢量字体写出「SipSession / 小酌场」，保证字清晰

资源：

```
LaunchPortrait.imageset/LaunchPortrait@2x.png     860 × 1920
LaunchPortrait.imageset/LaunchPortrait@3x.png     1290 × 2880
LaunchLandscape.imageset/LaunchLandscape@2x.png   1920 × 860
LaunchLandscape.imageset/LaunchLandscape@3x.png   2880 × 1290
```

比例故意比常见手机再长一些（约 2.23），这样刘海屏或矮屏只会裁到上下/左右的渐变，标志和文字留在中间安全区。图片用 Aspect Fill，背景色 `LaunchBackground` 是酒红 `#3C0613`，以免图片未加载时闪旧蓝底。

说明：当前 App 仍只支持竖屏（Info.plist 里 `UISupportedInterfaceOrientations` 只有 Portrait）。横屏开屏图已接到 storyboard 的 `heightClass = compact`，等以后开放横屏才会用到。

## 引导页 / 关于页锁头图

```
BrandLockup.imageset/  — 白底图标 + SipSession / 小酌场，已裁掉多余白边
BrandMark.imageset/    — 透明圆形标志，256 / 512 / 768，用于分享卡等小图标
```

`BrandLockup` 来自 `artwork/drinktrack-lockup.jpg`。那张图里的图标已经带圆角，只适合用在引导和关于页，不要拿去替换 AppIcon。

## 颜色

- `LaunchBackground`：`#3C0613`（开屏酒红）
- `AccentColor`：`#A82A24`（接近品牌酒红，替代原来的 `#256ABF`）

趋势图里原有的数据色没有跟着改，以免把图表语义改乱。

## 不要做的事

- 不要把 `drinktrack-icon-cheers.jpg`（预切圆角）复制到 `AppIcon.appiconset/AppIcon.png`
- 不要给 App 图标加透明或先裁圆角
- 不要改 Bundle ID、Xcode 目标名或工程名
