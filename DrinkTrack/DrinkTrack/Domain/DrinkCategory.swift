import Foundation

/// §6.4 酒种类枚举。既有 8 类的 rawValue 保持不变，已保存的记录不会失效。
/// 本轮按中国市场常见喝法补了黄酒、烧酒、果酒、预调酒。
enum DrinkCategory: String, CaseIterable, Identifiable, Codable {
    case baijiu       // 白酒
    case beer         // 啤酒
    case redWine      // 红酒
    case huangjiu     // 黄酒
    case riceWine     // 米酒
    case sake         // 清酒
    case soju         // 烧酒
    case spirits      // 洋酒
    case cocktail     // 鸡尾酒
    case fruitWine    // 果酒
    case premix       // 预调酒
    case other        // 其他

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baijiu: return "白酒"
        case .beer: return "啤酒"
        case .redWine: return "红酒"
        case .huangjiu: return "黄酒"
        case .riceWine: return "米酒"
        case .sake: return "清酒"
        case .soju: return "烧酒"
        case .spirits: return "洋酒"
        case .cocktail: return "鸡尾酒"
        case .fruitWine: return "果酒"
        case .premix: return "预调酒"
        case .other: return "其他"
        }
    }

    var emoji: String {
        switch self {
        case .baijiu: return "🥃"
        case .beer: return "🍺"
        case .redWine: return "🍷"
        case .huangjiu: return "🍶"
        case .riceWine: return "🍚"
        case .sake: return "🍶"
        case .soju: return "🍾"
        case .spirits: return "🥂"
        case .cocktail: return "🍸"
        case .fruitWine: return "🍑"
        case .premix: return "🥤"
        case .other: return "🍹"
        }
    }

    /// SF Symbols used on the dashboard mix and glance cards. Stick to symbols
    /// that exist on iOS 17 (deployment target).
    var systemImage: String {
        switch self {
        case .baijiu: return "wineglass"
        case .beer: return "mug.fill"
        case .redWine: return "wineglass.fill"
        case .huangjiu: return "cup.and.saucer.fill"
        case .riceWine: return "cup.and.saucer"
        case .sake: return "cup.and.saucer.fill"
        case .soju: return "wineglass"
        case .spirits: return "wineglass.fill"
        case .cocktail: return "wineglass"
        case .fruitWine: return "leaf.fill"
        case .premix: return "waterbottle.fill"
        case .other: return "drop.fill"
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
        case .huangjiu: return 0.14
        case .riceWine: return 0.12
        case .sake: return 0.15
        case .soju: return 0.17
        case .spirits: return 0.40
        case .cocktail: return 0.15 // MVP 统一估算，§8 R4 留给 P1 细化
        case .fruitWine: return 0.12
        case .premix: return 0.05
        case .other: return nil // 用户自定义或跳过换算
        }
    }

    /// §6.4 预设单杯容量选项（ml），用于 FR-DR-04 "杯数 × 单杯容量"输入方式。
    var presetVolumesML: [(label: String, ml: Double)] {
        switch self {
        case .baijiu: return [("小酒杯 15ml", 15), ("标准杯 50ml", 50), ("大碗 100ml", 100)]
        case .beer: return [("听装 330ml", 330), ("瓶装 500ml", 500), ("扎啤 500ml", 500)]
        case .redWine: return [("标准杯 150ml", 150), ("大号杯 250ml", 250)]
        case .huangjiu: return [("酒盅 50ml", 50), ("黄酒碗 100ml", 100), ("瓶装 500ml", 500)]
        case .sake: return [("小酒杯 40ml", 40), ("标准杯 180ml", 180)]
        case .soju: return [("烧酒杯 50ml", 50), ("瓶装 360ml", 360)]
        case .spirits: return [("标准杯 30ml", 30), ("加冰纯饮 45ml", 45)]
        case .cocktail: return [("标准杯 200ml", 200)]
        case .riceWine: return [("饭碗 250ml", 250), ("大碗 500ml", 500)]
        case .fruitWine: return [("标准杯 150ml", 150), ("小瓶 330ml", 330)]
        case .premix: return [("罐装 330ml", 330), ("罐装 500ml", 500)]
        case .other: return []
        }
    }

    /// 该类目最常见的几款，用于录入页的快捷候选。完整列表和搜索见 BrandLibrary。
    var presetBrands: [String] {
        BrandLibrary.items(in: self).prefix(8).map(\.name)
    }
}
