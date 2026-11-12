import Foundation

/// §6.6 标准饮品换算规则。
///
/// 口径说明（修复 PRD 文档内的公式矛盾，详见本次给用户的建议②）：
/// PRD §6.6 表格的"换算公式"列写的是 `ml × 0.42 × 0.789 / 10`（ABV 用小数），
/// 和表格里"1 标准饮品 ≈ 30ml（白酒）"的示例数值是吻合的：
///     30 × 0.42 × 0.789 / 10 ≈ 0.994 ≈ 1 标准饮品 ✓
/// 但紧接着的"换算说明"文字描述成 "标准饮品数 = 酒精含量(%) × ml × 0.789(乙醇密度) / 10"，
/// 如果字面理解把 "酒精含量(%)" 代入整数 42 而不是 0.42，结果会差 100 倍。
/// 本实现严格按表格里验证过的小数口径计算，务必不要改成整数 ABV。
struct StandardDrinkConverter {
    /// 乙醇密度（g/ml），WHO/通用值。
    static let ethanolDensity = 0.789

    /// 1 标准饮品 = 10g 纯酒精（WHO 标准饮品定义，PRD §6.6 决策背景 Q3）。
    static let gramsPerStandardDrink = 10.0

    /// - Parameters:
    ///   - volumeML: 饮用量，单位 ml
    ///   - abvFraction: 酒精含量，**小数**形式（如 42% 传 0.42，不是 42）
    /// - Returns: 标准饮品数，保留 2 位小数的精度交给调用方格式化
    static func standardDrinks(volumeML: Double, abvFraction: Double) -> Double {
        guard volumeML > 0, abvFraction > 0 else { return 0 }
        let grams = volumeML * abvFraction * ethanolDensity
        return grams / gramsPerStandardDrink
    }

    /// 便捷方法：按酒种类的典型 ABV 换算；「其他」类目没有默认 ABV，需要调用方传入自定义值，
    /// 不传则返回 nil，UI 层应展示"跳过换算，仅显示原始 ml"（对应 §6.6 「其他」行为）。
    static func standardDrinks(volumeML: Double, category: DrinkCategory, customABVFraction: Double? = nil) -> Double? {
        guard let abv = customABVFraction ?? category.typicalABVFraction else { return nil }
        return standardDrinks(volumeML: volumeML, abvFraction: abv)
    }

    /// 格式化展示，如 "≈ 0.8 标准饮品"（FR-DR-04 要求的实时展示文案）。
    static func formatted(_ standardDrinks: Double) -> String {
        String(format: "≈ %.1f 标准饮品", standardDrinks)
    }
}

// MARK: - 手算核对用例（供 README 里的验证步骤引用，不是真正的 XCTest，
// 后续轮次补单元测试 target 时可以直接把这些断言搬进 XCTestCase）。
//
// 500ml 啤酒，ABV 4%：
//   standardDrinks(volumeML: 500, abvFraction: 0.04)
//   = 500 * 0.04 * 0.789 / 10 = 1.578 ≈ 1.6 标准饮品
//
// 50ml 白酒（标准杯），ABV 42%：
//   standardDrinks(volumeML: 50, abvFraction: 0.42)
//   = 50 * 0.42 * 0.789 / 10 = 1.6569 ≈ 1.7 标准饮品
