import SwiftUI

/// 主界面 Tab 容器：仪表盘 / 趋势 / 好友 / 我的。
///
/// 「我的」放在最右侧（iOS 习惯位置），个人基础信息、健康连接、设置都收在这里。
struct RootView: View {
    let friendRepository: FriendRepository

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("仪表盘", systemImage: "waveform.path.ecg") }

            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }

            FriendFeedView(repository: friendRepository)
                .tabItem { Label("好友", systemImage: "person.2") }

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(DesignSystem.heartRateLine)
    }
}
