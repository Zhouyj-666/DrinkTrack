import Foundation

/// §6.4 酒种类枚举（P0 预置）。
enum DrinkCategory: String, CaseIterable, Identifiable, Codable {
    case baijiu       // 白酒
    case beer         // 啤酒
    case redWine      // 红酒
    case sake         // 清酒
    case spirits      // 洋酒
    case cocktail     // 鸡尾酒
    case riceWine     // 米酒
    case other        // 其他

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baijiu: return "白酒"
        case .beer: return "啤酒"
        case .redWine: return "红酒"
        case .sake: return "清酒"
        case .spirits: return "洋酒"
        case .cocktail: return "鸡尾酒"
        case .riceWine: return "米酒"
        case .other: return "其他"
        }
    }

    var emoji: String {
        switch self {
        case .baijiu: return "🥃"
        case .beer: return "🍺"
        case .redWine: return "🍷"
        case .sake: return "🍶"
        case .spirits: return "🥂"
        case .cocktail: return "🍸"
        case .riceWine: return "🍚"
        case .other: return "🍹"
        }
    }

    /// §6.6 典型酒精含量（vol%），以**小数**表示（0.42 而不是 42）。
    /// PRD §6.6 表格公式列本身是对的（ml × 0.42 × 0.789 / 10），
    /// 但文末"换算说明"文字写成"酒精含量(%)"容易被误读成整数 42 代入，
    /// 这里用代码把口径钉死为小数，并在换算器里写明注释，避免实现时踩这个坑。
    var typicalABVFraction: Double? {
        switch self {
        case .baijiu: return 0.42
        case .beer: return 0.04
        case .redWine: return 0.13
        case .sake: return 0.15
        case .spirits: return 0.40
        case .cocktail: return 0.15 // MVP 统一估算，§8 R4 留给 P1 细化
        case .riceWine: return 0.12
        case .other: return nil // 用户自定义或跳过换算
        }
    }

    /// §6.4 预设单杯容量选项（ml），用于 FR-DR-04 "杯数 × 单杯容量"输入方式。
    var presetVolumesML: [(label: String, ml: Double)] {
        switch self {
        case .baijiu: return [("小酒杯 15ml", 15), ("标准杯 50ml", 50), ("大碗 100ml", 100)]
        case .beer: return [("听装 330ml", 330), ("瓶装 500ml", 500), ("扎啤 500ml", 500)]
        case .redWine: return [("标准杯 150ml", 150), ("大号杯 250ml", 250)]
        case .sake: return [("小酒杯 40ml", 40), ("标准杯 180ml", 180)]
        case .spirits: return [("标准杯 30ml", 30), ("加冰纯饮 45ml", 45)]
        case .cocktail: return [("标准杯 200ml", 200)]
        case .riceWine: return [("饭碗 250ml", 250), ("大碗 500ml", 500)]
        case .other: return []
        }
    }

    /// §6.4 预设常见品牌（用于 FR-DR-03 搜索候选）。本地预置，不做联网搜索。
    var presetBrands: [String] {
        switch self {
        case .baijiu: return ["茅台", "五粮液", "泸州老窖", "汾酒", "剑南春"]
        case .beer: return ["百威", "青岛", "雪花", "喜力", "科罗娜"]
        case .redWine: return ["拉菲", "奔富", "张裕", "长城"]
        case .sake: return ["獭祭", "月桂冠", "菊正宗"]
        case .spirits: return ["轩尼诗", "芝华士", "伏特加", "龙舌兰"]
        case .cocktail: return ["Mojito", "Margarita", "Cosmopolitan", "Daiquiri", "Negroni",
                                 "Old Fashioned", "Pina Colada", "Whiskey Sour", "Martini", "Manhattan"]
        case .riceWine: return []
        case .other: return []
        }
    }
}
