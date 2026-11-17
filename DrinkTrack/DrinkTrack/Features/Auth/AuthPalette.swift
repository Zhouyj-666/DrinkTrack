import SwiftUI

/// Account-screen colors. These alias the app-wide burgundy / warm cream tokens
/// in DesignSystem so the login screens stay in the same family as 仪表盘 and 我的.
enum AuthPalette {
    static var burgundy: Color { DesignSystem.burgundy }
    static var burgundySoft: Color { DesignSystem.burgundyDark }
    static var amber: Color { DesignSystem.warningGold }
    static var cream: Color { DesignSystem.pagePlane }
    static var page: Color { DesignSystem.pagePlane }
    static var card: Color { DesignSystem.card }
    static var ink: Color { DesignSystem.primaryInk }
    static var secondary: Color { DesignSystem.secondaryInk }
    static var muted: Color { DesignSystem.mutedInk }
    static var danger: Color { DesignSystem.statusCritical }
}
