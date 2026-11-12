# DrinkTrack — 第一轮 iOS 工程交付说明

> **没有 Mac？** 看 [iPhone测试指南.md](iPhone测试指南.md) —— 用 GitHub Actions 在云端 Mac 上编译，
> 再用 Sideloadly 在 Windows 上装进 iPhone，全程不需要自己有 Mac。
> 下面这份 README 是给**有 Mac、用 Xcode 直接打开**的情况看的。

本目录下的 `DrinkTrack/` 是一个可以直接用 Xcode 打开的 iOS App 工程，对应 PRD v0.2 的
P0 范围子集（详见下方"本轮范围"）。工程文件（`.xcodeproj/project.pbxproj`）是在没有
Xcode 的 Windows 环境下手工构造生成的——生成前后都做了自动化一致性校验（见"已做的校验"），
但**没有在真正的 Xcode 里打开验证过**，如果遇到问题请参考下面的排查步骤。

## 环境要求

- macOS + Xcode 15.3 或更高版本（工程用的是 Xcode 15+ 的新版 pbxproj 格式，`objectVersion = 56`）
- iOS 17.0+（`IPHONEOS_DEPLOYMENT_TARGET = 17.0`）
- 一台 iPhone（真机测试 HealthKit 几乎是必须的——模拟器没有真实健康数据，很多查询会返回空）
- 一个 Apple Developer 账号（免费账号即可用于真机调试，HealthKit 能力需要账号支持）

## 打开工程

1. 双击 `DrinkTrack/DrinkTrack.xcodeproj`
2. 选中 `DrinkTrack` target → `Signing & Capabilities`，把 `Team` 改成你自己的开发者账号
   （`CODE_SIGN_STYLE` 已设为 `Automatic`，Xcode 会自动处理 Bundle Identifier 冲突；
   如果 `com.drinktrack.app` 已被占用，顺手改一下 `PRODUCT_BUNDLE_IDENTIFIER` 即可）
3. 确认 `Signing & Capabilities` 里能看到 `HealthKit` 这一项（entitlements 文件里已经声明了，
   正常情况下 Xcode 打开后会自动识别；如果没有显示，手动点 `+ Capability` 加一下 `HealthKit`）
4. 选择一台真机作为运行目标，Run

## 如果 Xcode 提示文件缺失 / 红色文件

手工构造的工程文件理论上和磁盘文件是严格一一对应的（生成时跑过自动校验，见下），但如果打开后
仍然看到红色的缺失文件：
1. 选中那个红色文件，在右侧 File Inspector 里看它期望的路径
2. 对照 `DrinkTrack/DrinkTrack/` 下实际的目录结构，用 "Add Files to DrinkTrack…" 重新关联，
   或者直接把 `Location` 改成正确的相对路径
3. 这种问题应该只会零星出现在个别文件上，不会是系统性的——如果大面积出现，请把报错截图发给我，
   大概率是我这边生成逻辑有遗漏

## 已做的校验（没有 Xcode 情况下能做到的程度）

- 生成前：逐一确认 `project.pbxproj` 里打算引用的每个文件在磁盘上真实存在
- 生成后：自动校验 pbxproj 内部所有 106 个对象 ID 互相引用一致（无悬空引用），
  以及磁盘上所有 38 个相关文件（36 个 .swift + Info.plist + entitlements）都能在
  pbxproj 里找到对应的 `path = 文件名;` 条目
- 没有做到、需要你在 Mac 上验证的：Xcode 实际打开解析、编译器类型检查、Core Data 模型 codegen

## 本轮范围（第一轮，对应 PRD P0 子集）

已实现：
- 首次启动合规引导：免责声明（FR-LEGAL-01）→ 隐私政策勾选（FR-LEGAL-02）→ HealthKit 授权引导
  → 基础信息采集（§7：性别/出生年份/体重/安静心率）→ 好友码展示
- HealthKit 采集（FR-HK-01~04/06）：心率、血氧、HRV（原生 SDNN）、睡眠
- 饮酒手工录入全流程（FR-DR-01~05）：种类/品牌/剂量（ml 或杯数）/标准饮品换算/时间/备注
- 实时仪表盘（FR-DASH-01~04）：心率曲线+饮酒标记、血氧展示、被动预警（**6 秒**自动消失，
  原 PRD 是 2 秒，见下方"给产品的建议"）、会话开始/结束、6 小时无录入自动归档
- 长期趋势报告（FR-TREND-01~03）：饮酒频率、按酒种类堆叠的饮酒量趋势（ml/标准饮品数双单位）、
  饮酒日 vs 非饮酒日心率+HRV 对比
- 本地 Core Data 存储 + 一键清除数据（§6.1）
- 轻量社交 UI（FR-SOC-01~03）：好友码生成/扫码/分享、好友动态 feed、打卡分享卡片——
  **这部分数据源是本地 mock 数据**，不连接真实后端，详见下方说明

本轮**未实现**，留给后续轮次：
- Apple Watch 伴侣 App（酒桌游戏 FR-GAME-*、身体状态挑战 FR-CHALL-* 都依赖 Watch，且这两个
  模块本身是 PRD 里的 P1）
- 真实的好友跨设备同步（需要后端或 CloudKit 公共数据库）
- iCloud 真实加密同步（设置页有开关 UI，但标注"即将推出"，没有接 `NSPersistentCloudKitContainer`）
- 个性化洞察（PRD 里也明确标注是 P1）

## 关于 Mock 数据的社交模块

`FriendRepository.swift` 是一个 protocol，当前只接了 `MockFriendRepository`（内存里固定几条
示例好友和动态，不发任何网络请求）。这样设计是为了让好友相关的 UI/交互先跑通，但不假装"已经能
加到真实好友"——等后续要接 CloudKit 或自建后端时，只需要新写一个实现这个 protocol 的类，
`DrinkTrackApp.swift` 里换掉注入的实例即可，UI 层代码不用改。

## 给产品的建议落地情况（对应之前的 PRD 审阅意见）

1. **AFib 异常心律功能默认关闭**：`FeatureFlags.afibDisplayDefaultEnabled = false`，
   设置页"实验性功能"里可以手动打开（会先弹 FR-LEGAL-04 额外免责）。法务文案定稿前不建议默认开启。
2. **标准饮品换算公式口径已按小数 ABV 实现**：`StandardDrinkConverter.swift` 里有详细注释，
   修复了 PRD §6.6 文字说明和表格公式字面不一致的问题，建议把 PRD 文档本身也同步改一下措辞。
3. **被动预警弹窗改成 6 秒自动消失**（PRD 原文是 2 秒），`AlertToastView.swift` 里有注释说明。
4. **技术栈约束**：本轮产出是真实 Swift/SwiftUI 源码，但生成/校验都是在 Windows 环境下完成的，
   没有 Xcode 实际编译验证过，这是本轮交付已知的、经你确认接受的风险。

## 验证步骤建议（在 Mac 上）

1. Xcode 打开工程，确认导航栏里没有红色文件（见上方排查步骤）
2. 选一个模拟器，`Cmd+B` 编译一次，确认没有语法错误
3. 换真机运行，走一遍首次启动引导流程，确认能正常跳到系统 HealthKit 授权弹窗
4. 开始一个饮酒会话，录入一条"啤酒 500ml"，确认换算结果显示 **≈ 1.6 标准饮品**
   （手算核对：500 × 0.04 × 0.789 ÷ 10 = 1.578 ≈ 1.6，对应 `StandardDrinkConverter.swift`
   底部的注释用例）
5. 结束会话，去"趋势"页看看饮酒频率/趋势图表是否正常渲染（Swift Charts 需要真实设备或
   iOS 17+ 模拟器）

## 目录结构

```
DrinkTrack/                         ← Xcode 工程根目录（双击 .xcodeproj 打开）
├─ DrinkTrack.xcodeproj/
└─ DrinkTrack/                      ← 源码
   ├─ DrinkTrackApp.swift           ← App 入口
   ├─ Info.plist / DrinkTrack.entitlements
   ├─ Model/                        ← Core Data 模型 + PersistenceController
   ├─ HealthKit/                    ← HealthKitManager（采集/查询）
   ├─ Domain/                       ← 换算规则、预警阈值、自动归档等纯逻辑
   ├─ Repositories/                 ← DrinkRepository / FriendRepository
   ├─ Features/                     ← 按模块划分的 SwiftUI 界面
   │   ├─ Onboarding / Dashboard / DrinkLogging / Trends / Social / Settings
   └─ Shared/                       ← 配色系统（DesignSystem）、免责文案、Tab 容器

_build-tools/                       ← 内部工具，生成 project.pbxproj 用，交付物不需要碰它
```
