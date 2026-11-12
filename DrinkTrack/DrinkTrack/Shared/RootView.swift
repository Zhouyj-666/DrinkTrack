import SwiftUI

/// 主界面 Tab 容器：仪表盘 / 记录 / 趋势 / 好友 / 设置。
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

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(DesignSystem.heartRateLine)
    }
}
