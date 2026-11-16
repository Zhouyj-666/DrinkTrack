import SwiftUI

/// Root tabs. `selectedTab` lets the dashboard jump to 路书 without nesting another map.
enum AppTab: Hashable {
    case dashboard
    case trends
    case map
    case friends
    case profile
}

/// 主界面 Tab 容器：仪表盘 / 趋势 / 地图 / 好友 / 我的。
///
/// 「我的」放在最右侧（iOS 习惯位置），个人基础信息、健康连接、设置都收在这里。
struct RootView: View {
    let friendRepository: FriendRepository
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem { Label("仪表盘", systemImage: "waveform.path.ecg") }
                .tag(AppTab.dashboard)

            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trends)

            DrinkingMapView()
                .tabItem { Label("地图", systemImage: "map") }
                .tag(AppTab.map)

            FriendFeedView(repository: friendRepository)
                .tabItem { Label("好友", systemImage: "person.2") }
                .tag(AppTab.friends)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(DesignSystem.heartRateLine)
    }
}