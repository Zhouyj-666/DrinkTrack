import SwiftUI

/// Brand chrome for 小酌场 / SipSession.
///
/// Light tokens follow the logo-matching mockups (warm cream, burgundy, amber).
/// Dark tokens use burgundy-tinted warm surfaces, not cold blue-gray.
enum DesignSystem {

    // MARK: Surfaces & ink
    static let pagePlane = Color(light: "#F6EFE6", dark: "#1A1412")
    static let card = Color(light: "#FFFFFF", dark: "#2B211E")
    static let chartSurface = card
    static let primaryInk = Color(light: "#1A1210", dark: "#F6EFE6")
    static let secondaryInk = Color(light: "#8A7D74", dark: "#A89890")
    static let mutedInk = Color(light: "#8A7D74", dark: "#A89890")
    static let muted2 = Color(light: "#B0A49B", dark: "#7D716B")
    static let gridline = Color(light: "#EDE3D8", dark: "#3D302C")
    static let baseline = Color(light: "#EDE3D8", dark: "#3D302C")
    static let separator = gridline
    static let tabBarBackground = Color(light: "#FFFCF9", dark: "#1F1816")
    static let tabBarUnselected = Color(light: "#B0A49B", dark: "#8A7D74")

    // MARK: Brand burgundy
    static let burgundy = Color(light: "#7A1A28", dark: "#E8A0A8")
    static let burgundyDark = Color(light: "#5A101C", dark: "#C97880")
    static let burgundySoft = Color(light: "#F6E8EA", dark: "#3A2226")
    static let primaryButtonTop = Color(hex: "#8F2434")
    static let primaryButtonBottom = Color(hex: "#68141F")

    static let warningGold = Color(hex: "#B8811E")
    static let success = Color(hex: "#2F8A5A")
    static let successSoft = Color(light: "#E8F6EE", dark: "#1C3A2A")

    static let beer = Color(hex: "#E08A2A")
    static let beerSoft = Color(light: "#FBE8D2", dark: "#3A2A18")
    static let riceWine = Color(hex: "#D48B93")
    static let riceWineSoft = Color(light: "#F8E4E6", dark: "#3A2226")

    /// 心率曲线：品牌酒红，不用原来的冷蓝色。
    static var heartRateLine: Color { Color(light: "#9A2432", dark: "#E0707C") }
    static var spo2Line: Color { Color(light: "#7A1A28", dark: "#E8A0A8") }

    static let statusGood = success
    static let statusWarning = warningGold
    static let statusSerious = Color(hex: "#C45A2A")
    static let statusCritical = Color(hex: "#7A1A28")

    // Warm categorical palette. Beer and rice wine stay locked to the mockup.
    static let categorical: [Color] = [
        Color(hex: "#6B3A2A"), // baijiu
        beer,                  // beer
        Color(hex: "#7A1A28"), // redWine
        Color(hex: "#C9A04A"), // huangjiu
        riceWine,              // riceWine
        Color(hex: "#C45A4A"), // sake
        Color(hex: "#B8811E"), // soju
        Color(hex: "#5A101C"), // spirits
        Color(hex: "#D48B93"), // cocktail
        Color(hex: "#E08A2A"), // fruitWine
        Color(hex: "#8A7D74"), // premix
        Color(hex: "#B0A49B"), // other
    ]

    static func color(for category: DrinkCategory) -> Color {
        let index = DrinkCategory.allCases.firstIndex(of: category) ?? 0
        return categorical[index % categorical.count]
    }

    static func softColor(for category: DrinkCategory) -> Color {
        switch category {
        case .beer: return beerSoft
        case .riceWine: return riceWineSoft
        default: return color(for: category).opacity(0.16)
        }
    }

    static let cardCorner: CGFloat = 18
    static let cardSpacing: CGFloat = 8
    static let screenPadding: CGFloat = 16

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [primaryButtonTop, primaryButtonBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Tab bar, navigation bar, and tint so every tab shares the warm chrome.
    @MainActor
    static func applyChrome() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#1F1816")
                : UIColor(hexString: "#FFFCF9")
        }
        let unselected = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#8A7D74")
                : UIColor(hexString: "#B0A49B")
        }
        let selected = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#E8A0A8")
                : UIColor(hexString: "#7A1A28")
        }
        let item = tab.stackedLayoutAppearance
        item.normal.iconColor = unselected
        item.normal.titleTextAttributes = [.foregroundColor: unselected]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]
        tab.shadowColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#3D302C")
                : UIColor(hexString: "#E8DDD3")
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().unselectedItemTintColor = unselected
        UITabBar.appearance().tintColor = selected

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        let page = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#1A1412")
                : UIColor(hexString: "#F6EFE6")
        }
        let ink = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexString: "#F6EFE6")
                : UIColor(hexString: "#1A1210")
        }
        nav.backgroundColor = page
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink]
        nav.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = selected
    }
}

extension View {
    func sipCard() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCorner, style: .continuous))
            .shadow(color: Color(red: 90 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.04), radius: 2, y: 1)
    }

    func sipScreenBackground() -> some View {
        self.background(DesignSystem.pagePlane.ignoresSafeArea())
    }
}

struct SipPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(DesignSystem.primaryButtonGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: "#68141F").opacity(configuration.isPressed ? 0.12 : 0.28), radius: 8, y: 4)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SipOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(DesignSystem.burgundy)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(DesignSystem.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignSystem.burgundy, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

extension Color {
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(hexString: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: String) {
        self.init(uiColor: UIColor(hexString: hex))
    }
}

extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
