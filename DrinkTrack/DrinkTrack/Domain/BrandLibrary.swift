import Foundation

/// FR-DR-03 品牌 / 酒款库：本地预置约 526 款中国市场常见酒款，可按名称、全拼或拼音首字母搜索。
///
/// - 只在本机搜索，不联网。
/// - 每款带一个**参考酒精度**（不同规格、批次会有差异），选中后会自动填进录入页的
///   「酒精度」，用来算标准饮品数；用户随时可以手动改。
/// - 数据用一段纯文本内嵌（`代码|名称|酒精度%`），而不是几百个结构体字面量，
///   避免 Swift 编译器在超大数组字面量上做类型推断时变得很慢。
struct BrandItem: Identifiable, Hashable {
    let name: String
    let category: DrinkCategory
    /// 参考酒精度，百分比数值（53 表示 53%vol）。
    let abvPercent: Double

    var id: String { category.rawValue + "|" + name }
    var abvFraction: Double { abvPercent / 100 }

    var abvText: String {
        abvPercent == abvPercent.rounded()
            ? String(format: "%.0f%%", abvPercent)
            : String(format: "%.1f%%", abvPercent)
    }
}

enum BrandLibrary {
    /// 全部酒款，按内嵌顺序（同一类目里大致按常见程度排序）。
    static let all: [BrandItem] = parse(rawData)

    /// 预先算好的搜索键：名称小写、拼音全拼、拼音首字母。
    private static let index: [(item: BrandItem, name: String, fullPinyin: String, initials: String)] = all.map { item in
        let keys = pinyinKeys(for: item.name)
        return (item, item.name.lowercased(), keys.full, keys.initials)
    }

    static func items(in category: DrinkCategory) -> [BrandItem] {
        all.filter { $0.category == category }
    }

    static func item(named name: String, category: DrinkCategory? = nil) -> BrandItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category, let match = all.first(where: { $0.category == category && $0.name == trimmed }) {
            return match
        }
        return all.first { $0.name == trimmed }
    }

    /// 搜索酒款。空关键字时返回该类目的常见酒款；有关键字时搜全库，
    /// 当前类目的结果排在前面（输入「茅台」时就算选着啤酒，也能找到白酒）。
    static func search(_ query: String, preferredCategory: DrinkCategory?, limit: Int = 30) -> [BrandItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "")
        if q.isEmpty {
            guard let preferredCategory else { return Array(all.prefix(limit)) }
            return Array(items(in: preferredCategory).prefix(limit))
        }
        var scored: [(item: BrandItem, score: Int, order: Int)] = []
        for (order, entry) in index.enumerated() {
            let compactName = entry.name.replacingOccurrences(of: " ", with: "")
            var score: Int?
            if compactName.hasPrefix(q) {
                score = 0
            } else if compactName.contains(q) {
                score = 1
            } else if entry.initials.hasPrefix(q) {
                score = 2
            } else if entry.fullPinyin.hasPrefix(q) {
                score = 2
            } else if entry.fullPinyin.contains(q) || entry.initials.contains(q) {
                score = 3
            }
            guard var value = score else { continue }
            if let preferredCategory, entry.item.category != preferredCategory {
                value += 10
            }
            scored.append((entry.item, value, order))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
            .prefix(limit)
            .map { $0.item }
    }

    /// 「飞天茅台」-> full "feitianmaotai", initials "ftmt"。英文部分按单词取首字母。
    static func pinyinKeys(for name: String) -> (full: String, initials: String) {
        let latin = name.applyingTransform(.mandarinToLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? name
        let tokens = latin.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let full = tokens.joined()
        let initials = tokens.compactMap { token -> String? in
            guard let first = token.first else { return nil }
            // 数字整段保留（"1573"），字母只取首字母。
            return first.isNumber ? token : String(first)
        }.joined()
        return (full, initials)
    }

    private static func parse(_ raw: String) -> [BrandItem] {
        raw.split(separator: "\n").compactMap { line in
            // Trim so a CRLF checkout can never leave "\r" on the ABV field.
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let category = code(String(parts[0])),
                  let abv = Double(parts[2]) else { return nil }
            return BrandItem(name: String(parts[1]), category: category, abvPercent: abv)
        }
    }

    private static func code(_ value: String) -> DrinkCategory? {
        switch value {
        case "b": return .baijiu
        case "e": return .beer
        case "r": return .redWine
        case "s": return .sake
        case "x": return .spirits
        case "c": return .cocktail
        case "m": return .riceWine
        case "o": return .other
        default: return nil
        }
    }

    // 代码：b 白酒 / e 啤酒 / r 红酒（含葡萄酒、香槟）/ s 清酒（含烧酒）/ x 洋酒（含力娇酒）
    //       c 鸡尾酒 / m 米酒（含黄酒）/ o 其他（果酒、梅酒、预调酒、苹果酒）
    // 酒精度为常见规格的参考值，不同批次、规格可能不同。
    private static let rawData = """
b|飞天茅台|53
b|茅台王子酒|53
b|茅台迎宾酒|53
b|茅台1935|53
b|茅台生肖酒|53
b|贵州大曲|53
b|汉酱|51
b|赖茅|53
b|五粮液 普五|52
b|五粮液1618|52
b|五粮液 经典|52
b|五粮春|45
b|五粮醇|50
b|五粮特曲|52
b|尖庄|50
b|国窖1573|52
b|泸州老窖特曲|52
b|泸州老窖头曲|52
b|泸州老窖二曲|52
b|泸州老窖窖龄酒|52
b|泸州老窖黑盖|42
b|泸州老窖六年窖头曲|52
b|青花汾酒20|53
b|青花汾酒30|53
b|黄盖玻汾|53
b|红盖玻汾|42
b|老白汾|53
b|汾酒巴拿马|53
b|杏花村|42
b|竹叶青|45
b|水晶剑南春|52
b|剑南春珍藏级|52
b|绵竹大曲|52
b|洋河海之蓝|42
b|洋河天之蓝|42
b|洋河梦之蓝M3|52
b|洋河梦之蓝M6+|52
b|洋河大曲|55
b|双沟大曲|46
b|双沟珍宝坊|41.8
b|古井贡酒 古5|40.6
b|古井贡酒 古8|50
b|古井贡酒 古16|50
b|古井贡酒 古20|52
b|青花郎|53
b|红花郎|53
b|郎牌特曲|50
b|小郎酒|45
b|顺品郎|45
b|习酒窖藏1988|53
b|君品习酒|53
b|金质习酒|53
b|银质习酒|53
b|董酒|54
b|董酒国密|54
b|品味舍得|52
b|智慧舍得|52
b|沱牌特级|50
b|沱牌大曲|38
b|水井坊井台|52
b|水井坊臻酿八号|52
b|水井坊典藏|52
b|西凤酒15年|52
b|西凤酒绿瓶|45
b|西凤酒375|52
b|国缘四开|42
b|国缘对开|42
b|今世缘典藏|42
b|口子窖六年|41
b|口子窖十年|41
b|牛栏山陈酿|42
b|牛栏山二锅头|56
b|牛栏山百年红|38
b|红星二锅头|56
b|红星蓝瓶二锅头|43
b|永丰二锅头|42
b|衡水老白干 古法20|67
b|衡水老白干|41
b|酒鬼酒|52
b|内参酒|52
b|湘泉|38
b|白云边12年|42
b|白云边15年|42
b|白云边20年|53
b|稻花香|42
b|珍酒|53
b|金沙回沙酒|53
b|国台国标|53
b|钓鱼台|53
b|小糊涂仙|52
b|江小白|40
b|光良|42
b|中国劲酒|35
b|毛铺苦荞酒|42
b|金门高粱 白金龙|58
b|金门高粱 黑金龙|58
b|玉山高粱|58
b|景芝景阳春|38
b|宝丰酒|50
b|扳倒井|52
b|李渡|52
b|丰谷|50
b|宋河粮液|50
b|迎驾贡酒|42
b|金种子|42
b|高炉家|42
b|文王贡酒|42
b|仰韶彩陶坊|46
b|杜康|50
b|河套王|42
b|老村长|42
b|龙江家园|42
b|玉泉|42
b|北大仓|50
b|榆树钱|42
b|叙府|52
b|小角楼|50
b|潭酒|53
b|钓鱼台国宾酒|53
b|夜郎古|53
b|摘要酒|53
b|国台十五年|53
b|劲牌毛铺|42
b|二锅头（通用）|56
b|高粱酒（通用）|52
b|酱香型白酒（通用）|53
b|浓香型白酒（通用）|52
b|清香型白酒（通用）|53
e|青岛经典|4.0
e|青岛纯生|4.0
e|青岛啤酒白啤|4.0
e|青岛黑啤|4.3
e|青岛奥古特|5.0
e|青岛一厂皮尔森|4.0
e|青岛崂山啤酒|3.1
e|青岛清爽|3.1
e|青岛鸿运当头|5.0
e|雪花勇闯天涯|3.1
e|雪花纯生|3.6
e|雪花清爽|2.5
e|雪花脸谱|4.5
e|雪花马尔斯绿|4.5
e|雪花匠心营造|4.6
e|喜力 Heineken|5.0
e|喜力星银|4.0
e|百威 Budweiser|3.6
e|百威纯生|3.6
e|百威金尊|4.7
e|哈尔滨啤酒|3.6
e|哈尔滨冰纯|3.1
e|哈尔滨小麦王|3.6
e|燕京啤酒|3.6
e|燕京U8|3.3
e|燕京V10白啤|4.0
e|燕京鲜啤|3.3
e|珠江啤酒|3.6
e|珠江纯生|3.6
e|珠江97纯生|4.0
e|金威啤酒|3.6
e|重庆啤酒|3.1
e|山城啤酒|3.1
e|乌苏啤酒|4.0
e|大乌苏|4.0
e|红乌苏|4.0
e|大理啤酒|3.1
e|风花雪月|3.1
e|嘉士伯 Carlsberg|5.0
e|乐堡 Tuborg|4.0
e|1664白啤 Kronenbourg|5.0
e|1664桃红|4.5
e|科罗娜 Corona|4.5
e|时代啤酒 Stella Artois|5.0
e|福佳白 Hoegaarden|4.9
e|福佳玫瑰红|3.1
e|蓝带 Blue Ribbon|3.6
e|金星啤酒|3.1
e|鹅岛 Goose Island IPA|5.9
e|健力士 Guinness|4.2
e|朝日 Asahi|5.0
e|朝日超爽|5.0
e|麒麟一番榨 Kirin|5.0
e|三得利 Suntory|4.5
e|札幌 Sapporo|5.0
e|虎牌 Tiger|5.0
e|生力 San Miguel|5.0
e|贝克 Beck's|4.9
e|藍妹 Blue Girl|5.0
e|教士 Weihenstephaner|5.4
e|宝莱纳 Paulaner|5.5
e|范佳乐 Franziskaner|5.0
e|瓦伦丁 Wurenbacher|5.0
e|奥丁格 Oettinger|4.9
e|卡斯特 Castle|4.5
e|智美 Chimay 蓝帽|9.0
e|罗斯福10号 Rochefort|11.3
e|督威 Duvel|8.5
e|粉象 Delirium|8.5
e|林德曼 Lindemans|3.5
e|吉尼斯黑啤|4.2
e|麒麟淡丽|5.5
e|拳击猫|5.5
e|熊猫精酿|5.0
e|京A|5.5
e|大跃 Great Leap|5.0
e|高大师|5.0
e|牛啤堂|5.0
e|悠航 Slow Boat|5.0
e|优布劳|4.8
e|泰山原浆|3.6
e|泰山28天|3.6
e|崂山啤酒|3.1
e|千岛湖啤酒|3.1
e|金士百|3.1
e|天湖啤酒|3.6
e|漓泉啤酒|3.1
e|黄河啤酒|3.1
e|西夏啤酒|3.1
e|绿岛|3.1
e|惠泉|3.1
e|雪津|3.1
e|蓝剑|3.1
e|威海卫|3.1
e|趵突泉|3.1
e|银麦|3.1
e|K记精酿|5.0
e|Brewdog 朋克IPA|5.4
e|Sierra Nevada 内华达山脉|5.6
e|Stone IPA|6.9
e|Lagunitas IPA|6.2
e|福佳果味白啤|3.1
e|鲜啤（通用）|4.0
e|扎啤（通用）|4.0
e|精酿IPA（通用）|6.5
e|世涛 Stout（通用）|6.0
e|小麦白啤（通用）|5.0
e|皮尔森（通用）|4.8
e|无醇啤酒（通用）|0.5
r|拉菲传奇|13
r|拉菲珍宝|13
r|拉菲古堡|13
r|拉菲罗斯柴尔德奥希耶|13
r|木桐嘉棣|13
r|奔富Bin2|14
r|奔富Bin8|14
r|奔富Bin28|14.5
r|奔富Bin389|14.5
r|奔富Bin407|14.5
r|奔富洛神山庄|13.5
r|奔富寇兰山|13.5
r|黄尾袋鼠|13
r|杰卡斯 Jacob's Creek|13.5
r|禾富 Wolf Blass|13.5
r|御兰堡|13
r|干露 Concha y Toro|13.5
r|红魔鬼 Casillero del Diablo|13.5
r|活灵魂 Almaviva|14
r|蒙特斯 Montes|14
r|桑塔丽塔|13.5
r|拉图嘉利|13
r|柏菲|14
r|白马|14
r|玛歌|13
r|侯伯王|13.5
r|嘉露 Gallo|13
r|蒙大菲 Robert Mondavi|13.5
r|贝灵哲 Beringer|13.5
r|作品一号 Opus One|14.5
r|云雾之湾 Cloudy Bay|13
r|安东尼世家|13.5
r|西施佳雅|14
r|醉鹅娘|13
r|张裕解百纳|12
r|张裕爱斐堡|13
r|张裕摩塞尔|13
r|张裕干红|12
r|长城干红|12
r|长城五星|12
r|长城华夏葡园|12.5
r|长城桑干|13
r|王朝干红|12
r|威龙|12
r|贺兰山|13
r|怡园酒庄|13
r|银色高地|14
r|敖云|14.5
r|莫高|12
r|通化葡萄酒|7
r|新天|12
r|香槟 Moet 酩悦|12
r|凯歌香槟 Veuve Clicquot|12
r|唐培里侬 Dom Perignon|12.5
r|路易王妃 Cristal|12
r|巴黎之花|12
r|菲斯奈特 Freixenet|11.5
r|马天尼阿斯蒂|7
r|意大利起泡酒 Prosecco|11
r|莫斯卡托 Moscato|5.5
r|冰酒（通用）|11
r|赤霞珠（通用）|13.5
r|梅洛（通用）|13.5
r|黑皮诺（通用）|13
r|西拉（通用）|14
r|马尔贝克（通用）|13.5
r|霞多丽白葡萄酒（通用）|13
r|长相思白葡萄酒（通用）|12.5
r|雷司令（通用）|11
r|桃红葡萄酒（通用）|12
r|起泡酒（通用）|11.5
r|波特酒 Port|20
r|雪莉酒 Sherry|17
s|獭祭45|16
s|獭祭39|16
s|獭祭23|16
s|獭祭 Beyond|16
s|月桂冠|15
s|菊正宗|15
s|白鹤|14
s|大关|15
s|松竹梅|15
s|久保田千寿|15
s|久保田万寿|15
s|久保田百寿|15
s|八海山|15.5
s|十四代|15
s|黑龙|15
s|梵|15
s|贺茂鹤|15
s|上善如水|14
s|出羽樱|15
s|南部美人|15
s|醉鲸|16
s|新政|14
s|鹤龄|15
s|白鹿|15
s|日本盛|15
s|澪 MIO 起泡清酒|5
s|梅乃宿|15
s|浦霞|15
s|天狗舞|16
s|大七|15
s|喜久醉|15
s|雁木|15
s|东洋美人|16
s|清酒（通用）|15
s|烧酒 真露 Jinro|16.9
s|烧酒 初饮初乐|16.5
s|韩国烧酒 果味|13
s|玛格丽 米酒|6
s|日本烧酎|25
x|轩尼诗VSOP|40
x|轩尼诗XO|40
x|轩尼诗新点|40
x|人头马VSOP|40
x|人头马XO|40
x|人头马CLUB|40
x|马爹利名士|40
x|马爹利蓝带|40
x|马爹利VSOP|40
x|拿破仑 Courvoisier|40
x|芝华士12年|40
x|芝华士18年|40
x|尊尼获加红牌|40
x|尊尼获加黑牌|40
x|尊尼获加蓝牌|40
x|百龄坛|40
x|帝王 Dewar's|40
x|格兰菲迪12年|40
x|格兰威特12年|40
x|麦卡伦12年|40
x|麦卡伦18年|43
x|山崎|43
x|响 Hibiki|43
x|白州|43
x|三得利角瓶|40
x|余市|45
x|杰克丹尼 Jack Daniel's|40
x|占边 Jim Beam|40
x|美格 Maker's Mark|45
x|野火鸡 Wild Turkey|40.5
x|尊美醇 Jameson|40
x|威雀 Famous Grouse|40
x|乐加维林16年|43
x|拉弗格10年|40
x|雅柏10年|46
x|大摩12年|40
x|格兰杰10年|40
x|百富12年|40
x|绝对伏特加 Absolut|40
x|灰雁 Grey Goose|40
x|斯米诺 Smirnoff|40
x|雪树 Belvedere|40
x|苏连红|40
x|深蓝伏特加 Skyy|40
x|孤狼伏特加|40
x|奥美加 Olmeca 龙舌兰|38
x|豪帅快活 Jose Cuervo|38
x|唐胡里奥 Don Julio|40
x|培恩 Patron|40
x|懒虫龙舌兰|38
x|百加得白朗姆 Bacardi|40
x|摩根船长 Captain Morgan|35
x|哈瓦那俱乐部 Havana Club|40
x|美雅士 Myers's|40
x|孟买蓝宝石金酒 Bombay|40
x|哥顿金酒 Gordon's|37.5
x|添加利金酒 Tanqueray|43.1
x|亨利爵士金酒 Hendrick's|41.4
x|必富达金酒 Beefeater|40
x|植物学家金酒 The Botanist|46
x|季之美金酒 Roku|43
x|野格 Jagermeister|35
x|百利甜 Baileys|17
x|甘露咖啡力娇酒 Kahlua|20
x|君度 Cointreau|40
x|金巴利 Campari|25
x|阿佩罗 Aperol|11
x|马天尼威末酒 Martini|15
x|马利宝 Malibu|21
x|绿薄荷力娇酒|24
x|杏仁力娇酒 Disaronno|28
x|苦艾酒 Absinthe|68
x|白兰地（通用）|40
x|威士忌（通用）|40
x|伏特加（通用）|40
x|龙舌兰（通用）|40
x|朗姆酒（通用）|40
x|金酒（通用）|40
x|力娇酒（通用）|20
c|Mojito 莫吉托|12
c|Margarita 玛格丽特|20
c|Cosmopolitan 大都会|20
c|Daiquiri 代基里|20
c|Negroni 尼格罗尼|24
c|Old Fashioned 古典|30
c|Pina Colada 椰林飘香|12
c|Whiskey Sour 威士忌酸|15
c|Martini 马天尼|30
c|Manhattan 曼哈顿|30
c|Long Island 长岛冰茶|22
c|Gin Tonic 金汤力|10
c|Highball 嗨棒|8
c|Moscow Mule 莫斯科骡子|10
c|Tequila Sunrise 龙舌兰日出|12
c|Bloody Mary 血腥玛丽|12
c|Cuba Libre 自由古巴|10
c|Screwdriver 螺丝起子|10
c|Sex on the Beach 激情海岸|12
c|Aperol Spritz 阿佩罗气泡|11
c|Espresso Martini 浓缩咖啡马天尼|20
c|Mai Tai 迈泰|20
c|Blue Hawaii 蓝色夏威夷|12
c|B-52 轰炸机|26
c|Kamikaze 神风特攻队|25
c|White Russian 白俄罗斯|20
c|Black Russian 黑俄罗斯|30
c|Paloma 帕罗玛|10
c|Tom Collins 汤姆柯林斯|10
c|French 75 法式75|15
c|Sidecar 边车|25
c|Gimlet 吉姆雷特|25
c|Dry Martini 干马天尼|32
c|Boulevardier 花花公子|25
c|Mint Julep 薄荷朱利普|25
c|Sangria 桑格利亚|10
c|Mimosa 含羞草|8
c|Bellini 贝利尼|8
c|Irish Coffee 爱尔兰咖啡|12
c|深水炸弹|10
c|特调（通用）|15
c|Shot 子弹杯（通用）|35
m|古越龙山|14
m|古越龙山 花雕|14
m|会稽山|14
m|塔牌|14
m|女儿红|14
m|石库门|11
m|和酒|12
m|沙洲优黄|12
m|即墨老酒|11.5
m|绍兴黄酒（通用）|15
m|加饭酒|15
m|花雕酒（通用）|15
m|状元红|14
m|孔乙己|14
m|醪糟（通用）|1
m|客家米酒|12
m|桂花米酒|10
m|江南米酒|6
m|十里香米酒|10
m|孝感米酒|1
m|贵州糯米酒|10
m|日本甘酒|1
m|朝鲜马格利|6
o|锐澳RIO 微醺|3
o|锐澳RIO 强爽|8
o|锐澳RIO 清爽|5
o|梅见青梅酒|12
o|梅见金梅见|20
o|俏雅梅酒 Choya|10
o|三得利和乐怡 Horoyoi|3
o|三得利-196 冰结|5
o|麒麟冰结|5
o|江小白果立方|15
o|十七光年|12
o|贝瑞甜心|5
o|百加得冰锐|4.8
o|Smirnoff Ice|4.5
o|Strongbow 苹果酒|4.5
o|Somersby 苹果酒|4.5
o|苹果酒 Cider（通用）|5
o|梅酒（通用）|12
o|果酒（通用）|8
o|荔枝酒|12
o|桂花酒|12
o|青梅酒|12
o|杨梅酒|15
o|蓝莓酒|12
o|桑葚酒|12
o|预调鸡尾酒（通用）|5
o|气泡酒 Seltzer|5
o|白爪 White Claw|5
o|露酒（通用）|30
o|药酒（通用）|35
o|奶酒|15
o|马奶酒|8
o|青稞酒|42
"""
}
