import SwiftUI

/// 归档会话详情页 + FR-SOC-03 分享入口。
/// 这是 ShareCardView 实际被用户触达的地方——会话归档后，用户从历史记录列表点进来，
/// 点右上角「分享」生成打卡图片。
struct SessionDetailView: View {
    let session: DrinkSessionEntity
    @State private var includeHeartRateCurve = true
    @State private var renderedImage: Image?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SessionTimelineChart(session: session)
                Toggle("附加心率曲线截图", isOn: $includeHeartRateCurve)
                    .padding(.horizontal)

                ShareCardView(session: session, includeHeartRateCurve: includeHeartRateCurve)
            }
        }
        .navigationTitle("会话详情")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: renderedImage ?? Image(systemName: "wineglass"),
                    preview: SharePreview("DrinkTrack 饮酒打卡", image: renderedImage ?? Image(systemName: "wineglass"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .onAppear { renderShareImage() }
            }
        }
        .onChange(of: includeHeartRateCurve) { _, _ in renderShareImage() }
    }

    /// 把 ShareCardView 渲染成图片用于系统分享面板（FR-SOC-03：仅趋势不展示精确数值，
    /// 规则在 ShareCardView 内部已经处理，这里只负责把它变成一张图）。
    /// 注意：ImageRenderer 渲染的是一棵独立的 View 树，不会自动继承当前的 environmentObject，
    /// 必须显式把 HealthKitManager.shared 注入进去，否则 ShareCardView 里的
    /// @EnvironmentObject 在渲染时找不到依赖会直接崩溃。
    @MainActor
    private func renderShareImage() {
        let content = ShareCardView(session: session, includeHeartRateCurve: includeHeartRateCurve)
            .environmentObject(HealthKitManager.shared)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
