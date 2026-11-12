# DrinkTrack 装到 iPhone 上测试 —— 完整操作指南

> 适用场景：**没有 Mac，只有 Windows 电脑 + iPhone + Apple Watch**。
> 整条路线是：GitHub 云端 Mac 编译 → 下载 ipa → Windows 上用 Sideloadly 重签 → 装进 iPhone。

---

## 零、先搞清楚这条路的 3 个限制

在动手前先知道这些，省得中途踩坑了不知道为什么：

| 限制 | 影响 | 应对 |
|---|---|---|
| **免费 Apple ID 签名 7 天过期** | 每隔 7 天 App 会打不开，要重新用 Sideloadly 装一次（数据不会丢） | 能接受就继续；嫌烦就买 $99/年开发者账号，签名有效期变 1 年，还能用 TestFlight 免插线安装 |
| **免费 Apple ID 的 HealthKit 权限有不确定性** | 免费账号有一批 entitlement 用不了。HealthKit 大概率可以，但不是 100% 确定 | **这一步要最先验证**（见第五步）。如果读不到健康数据，基本只能上 $99 账号 |
| **GitHub Actions 的 macOS 额度** | 私有仓库免费额度 2000 分钟/月，但 **macOS 机器按 10 倍计费**，实际只有约 200 分钟/月。本工程一次编译大概 3-5 分钟 | 够用（约 40-60 次编译/月）。公开仓库则完全不限量，但代码会公开 |

---

## 一、准备：把代码推到 GitHub

你的电脑目前**没有装 git**，三种方式任选：

### 方式 A：GitHub Desktop（最推荐，图形界面）
1. 下载安装 https://desktop.github.com/
2. 用你的 GitHub 账号登录
3. `File` → `Add local repository` → 选 `E:\DrinkTrack`
4. 它会提示"这不是一个 git 仓库，要创建吗" → 点 **Create a repository**
5. 点 `Publish repository` → 取名 `DrinkTrack` → **取消勾选 "Keep this code private"**（公开仓库 Actions 不限量；介意的话勾上也行，额度够用）

### 方式 B：装 git 命令行
1. 下载 https://git-scm.com/download/win 安装
2. 在 GitHub 网页上新建一个空仓库 `DrinkTrack`（不要勾选 "Add a README file"）
3. 然后在 PowerShell 里执行（把 `你的用户名` 换掉）：
```powershell
cd E:\DrinkTrack
git init
git add .
git commit -m "DrinkTrack 第一轮：P0 子集"
git branch -M main
git remote add origin https://github.com/你的用户名/DrinkTrack.git
git push -u origin main
```

### 方式 C：网页直接拖文件（最笨但不用装东西）
GitHub 新建仓库 → `uploading an existing file` → 把 `E:\DrinkTrack` 里的东西拖进去。
⚠️ 注意：网页上传**容易漏掉以点开头的隐藏文件夹**（`.github`、`.gitignore`），
而 `.github/workflows/build.yml` 正是自动编译的核心，漏了就什么都不会发生。所以**不推荐这个方式**。

> **重要**：仓库根目录必须是 `E:\DrinkTrack`（而不是 `E:\DrinkTrack\DrinkTrack`），
> 因为 `.github/workflows/build.yml` 要在仓库根下，workflow 里写的路径也是按这个结构来的。

---

## 二、触发云端编译

推上去之后：
1. 打开你的 GitHub 仓库页面 → 点顶部 **Actions** 标签
2. 应该能看到一个正在跑的 **Build DrinkTrack IPA**（push 会自动触发）
3. 如果没自动跑：左侧点 `Build DrinkTrack IPA` → 右边 `Run workflow` → 绿色按钮

等 3-5 分钟。

### ⚠️ 第一次大概率会编译失败 —— 这是正常的

这份代码是在没有 Xcode 的 Windows 上写的，**从来没有被编译器检查过**。
第一次 CI 跑出 Swift 编译错误完全在预期内，这恰恰是用 CI 的最大价值。

**失败了怎么办**：
1. 点进失败的那次运行
2. 页面最下面 `Artifacts` 区域下载 **build-log**
3. 把 `build.log` 里的报错内容发给 Claude，我来修，修完重新 push 就会自动重编

---

## 三、下载 ipa

编译成功后（绿色 ✓）：
1. 点进这次运行的页面
2. 最下面 `Artifacts` → 下载 **DrinkTrack-ipa**
3. 解压出 `DrinkTrack.ipa`

---

## 四、Windows 上用 Sideloadly 签名安装

1. 下载安装 Sideloadly：https://sideloadly.io/ （免费，纯 Windows 工具）
   - 它依赖 iTunes 的驱动组件，如果没装过 iTunes，Sideloadly 会提示你装
2. iPhone 用数据线插电脑 → iPhone 上弹出"信任此电脑" → 点**信任** → 输入锁屏密码
3. 打开 Sideloadly：
   - `IPA file`：拖入 `DrinkTrack.ipa`
   - `Apple ID`：填你自己的 Apple ID
   - 点 **Start** → 会要求输入 Apple ID 密码（如果开了两步验证，需要用 App 专用密码，Sideloadly 会提示）
4. 等进度条走完，提示 `Done`

---

## 五、iPhone 上信任并首次启动（关键验证步骤）

1. iPhone：`设置` → `通用` → `VPN与设备管理` → 找到你的 Apple ID → 点 **信任**
2. 桌面上找到 **DrinkTrack** 图标，点开
3. 会依次走：免责声明 → 隐私政策 → **Apple Health 授权** → 基础信息 → 好友码

### 🔴 在"Apple Health 授权"这一步重点看

- **能正常弹出系统的健康数据授权页面** → HealthKit entitlement 签成功了，这条路通了 ✅
- **直接闪退、或者根本不弹授权页** → 免费账号的 HealthKit 权限没签上 ❌
  - 这种情况基本只能上 $99/年的 Apple Developer Program
  - 先把现象告诉 Claude，确认一下是不是代码本身的问题再决定要不要花钱

授权时记得把心率、血氧、HRV、睡眠**全部打开**（授权页面上要逐项开，或者点"全部打开"）。

---

## 六、功能验证清单

戴上 Apple Watch（心率/血氧/HRV 都来自 Watch，手表不戴就没数据），然后：

| # | 验证什么 | 怎么看 |
|---|---|---|
| 1 | **换算公式对不对** | 开始会话 → 加一条"啤酒 500ml" → 表单下方应显示 **≈ 1.6 标准饮品**（手算核对：500 × 0.04 × 0.789 ÷ 10 = 1.578） |
| 2 | **心率曲线有数据** | 仪表盘上应该能看到心率折线，而不是"手表未连接"。刚戴上手表可能要等几分钟才有数据写入 |
| 3 | **饮酒标记点** | 录入记录后，心率曲线上应出现 🍷 虚线标记 |
| 4 | **血氧模块** | 当前血氧数值 + 过去 1 小时折线；低于 95% 会变橙色 |
| 5 | **会话归档** | 点"结束会话" → 去"趋势"页 → 底部"历史记录"里应该能看到这次会话 |
| 6 | **分享打卡** | 历史记录点进任意一次会话 → 右上角分享按钮 → 应生成打卡图片 |
| 7 | **数据清除** | 设置 → 数据管理 → 清除所有数据（验证完再点，会清空） |

### 小技巧：不想等真实数据时手动造数据

iPhone 自带的"健康" App 里可以手动添加数据，用来快速验证图表渲染：
`健康` → `浏览` → `心脏` → `心率` → 右上角 `添加数据` → 填个数值和时间。
血氧、HRV 同理。这样不用真的等 Apple Watch 采样。

---

## 七、本轮没有的功能（别找了，确实没做）

- Apple Watch 上的 App（本轮只有 iPhone 端；Watch 只作为数据来源）
- 酒桌小游戏、身体状态挑战（PRD 里本来就是 P1）
- 真实的好友功能 —— 好友列表和动态**是写死的假数据**，不连任何服务器
- iCloud 同步（设置页开关是灰的，标着"即将推出"）
- 异常心律(AFib)展示 —— 默认关闭，在设置→实验性功能里可以手动开

---

## 八、每周要做的事（免费账号的代价）

签名 7 天后过期，App 会打不开。重新装一次即可：
1. iPhone 插电脑
2. 打开 Sideloadly，拖入同一个 `DrinkTrack.ipa`，Start
3. 本地数据不会丢（Core Data 存在 App 沙盒里，覆盖安装会保留）

改了代码想重新测：push 到 GitHub → 等 Actions 跑完 → 下新 ipa → Sideloadly 重装。

---

## 九、出问题时把这些发给 Claude

- **编译失败** → Actions 里下载的 `build.log`
- **Sideloadly 报错** → 它窗口里的红色报错文字截图
- **App 闪退** → iPhone `设置` → `隐私与安全性` → `分析与改进` → `分析数据` → 找 `DrinkTrack-...` 开头的崩溃日志
- **功能不对** → 描述现象 + 截图
