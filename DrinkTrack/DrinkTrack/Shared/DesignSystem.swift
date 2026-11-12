import SwiftUI

/// 图表 / UI 配色系统。
///
/// 配色严格按 `dataviz` skill 的方法论来：
/// - 心率曲线是单一数值的"幅度"编码 → 用 Sequential 单一蓝色色阶（非彩虹渐变）
/// - 血氧/预警状态走 Status 色板（good/warning/serious/critical），不挪用分类色
/// - 趋势报告里"按酒种类堆叠"的图表是 Categorical 编码 → 固定顺序取色，永不按排序重新上色
/// - 下面这组 hex 来自 dataviz skill 的 `references/palette.md` 验证过的默认色板
///   （色盲安全性、明暗双模式对比度都已跑过 validate_palette.js），如果以后要换成品牌色，
///   应该替换这里的数值并重新跑一次校验脚本，而不是随手改色号。
enum DesignSystem {

    // MARK: Chart chrome & ink（对应 palette.md「Chart chrome & ink」）
    static let chartSurface = Color(light: "#fcfcfb", dark: "#1a1a19")
    static let pagePlane = Color(light: "#f9f9f7", dark: "#0d0d0d")
    static let primaryInk = Color(light: "#0b0b0b", dark: "#f0efec")
    static let secondaryInk = Color(light: "#52514e", dark: "#c3c2b7")
    static let mutedInk = Color(light: "#898781", dark: "#898781")
    static let gridline = Color(light: "#e1e0d9", dark: "#2c2c2a")
    static let baseline = Color(light: "#c3c2b7", dark: "#383835")

    // MARK: Sequential（心率/血氧等单一幅度数值）—— 单一蓝色色阶，浅→深
    static let sequentialBlue100 = Color(hex: "#cde2fb")
    static let sequentialBlue400 = Color(light: "#3987e5", dark: "#3987e5")
    static let sequentialBlue500 = Color(light: "#256abf", dark: "#256abf")
    static let sequentialBlue700 = Color(hex: "#0d366b")

    /// 心率曲线主色（FR-DASH-01）
    static var heartRateLine: Color { sequentialBlue500 }
    /// 血氧曲线主色（FR-DASH-02），低于 95% 时切换成 warning
    static var spo2Line: Color { sequentialBlue500 }

    // MARK: Status（固定语义色，不复用为分类色；永远搭配 icon + 文字，不单独靠颜色传达）
    static let statusGood = Color(hex: "#0ca30c")
    static let statusWarning = Color(hex: "#fab219")
    static let statusSerious = Color(hex: "#ec835a")
    static let statusCritical = Color(hex: "#d03b3b")

    // MARK: Categorical（按固定顺序分配，8 种酒类正好对应 8 个槽位，顺序取自 palette.md）
    static let categorical: [Color] = [
        Color(light: "#2a78d6", dark: "#3987e5"), // 1 blue
        Color(light: "#eb6834", dark: "#d95926"), // 2 orange
        Color(light: "#1baf7a", dark: "#199e70"), // 3 aqua
        Color(light: "#eda100", dark: "#c98500"), // 4 yellow
        Color(light: "#e87ba4", dark: "#d55181"), // 5 magenta
        Color(light: "#008300", dark: "#008300"), // 6 green
        Color(light: "#6250d6", dark: "#9085e9"), // 7 violet
        Color(light: "#e34948", dark: "#e66767"), // 8 red
    ]

    /// 按 DrinkCategory 的固定枚举顺序取色，而不是按当前数据排序取色——
    /// 保证"啤酒永远是橙色"这种心智映射在不同视图之间保持一致。
    static func color(for category: DrinkCategory) -> Color {
        let index = DrinkCategory.allCases.firstIndex(of: category) ?? 0
        return categorical[index % categorical.count]
    }
}

extension Color {
    /// 支持根据当前颜色模式分别指定浅色/深色模式下的颜色（对应 palette.md 的双模式表）。
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(hexString: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: String) {
        self.init(uiColor: UIColor(hexString: hex))
    }
}

private extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
