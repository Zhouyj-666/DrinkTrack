import SwiftUI

/// 会话详情页 + FR-SOC-03 分享入口。
/// 从「趋势 > 历史记录」或仪表盘的「上一场」卡片进入：看本场时间轴、每一杯、地点，
/// 并在下方预览分享卡片，点右上角分享按钮发出去。
struct SessionDetailView: View {
    @ObservedObject var session: DrinkSessionEntity
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @State private var includeHeartRateCurve = true
    @State private var showLocationOnCard = UserPreferences.shareCardShowsLocation
    @State private var locationDraft = ""
    @State private var renderedImage: Image?
    @State private var sessionAlerts: [AlertThresholdEngine.AlertResult] = []
    @FocusState private var locationFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SessionTimelineChart(session: session)

                SessionAlertsCard(alerts: sessionAlerts)

                locationEditor

                SessionLogListView(session: session, sessionIsActive: session.status == "active")

                VStack(alignment: .leading, spacing: 8) {
                    Text("分享卡片").font(.headline)
                    Toggle("附加本场心率走势", isOn: $includeHeartRateCurve)
                    Toggle("在卡片上显示地点", isOn: $showLocationOnCard)
                        .disabled((session.locationName ?? "").isEmpty)
                    Text("卡片不会包含花费；心率只显示走势，不显示数值。")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                .padding()
                .background(DesignSystem.chartSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ShareCardView(session: session, includeHeartRateCurve: includeHeartRateCurve, showLocation: showLocationOnCard)
                    .frame(maxWidth: ShareCardView.renderWidth)

                if let renderedImage {
                    ShareLink(
                        item: renderedImage,
                        preview: SharePreview("DrinkTrack 饮酒打卡", image: renderedImage)
                    ) {
                        Label("分享这张卡片", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal)
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
                .accessibilityLabel("分享")
            }
        }
        .onAppear {
            locationDraft = session.locationName ?? ""
            sessionAlerts = AlertThresholdEngine.decode(session.value(forKey: "alertsJSON") as? String)
            renderShareImage()
        }
        .onChange(of: includeHeartRateCurve) { _, _ in renderShareImage() }
        .onChange(of: showLocationOnCard) { _, newValue in
            UserPreferences.shareCardShowsLocation = newValue
            renderShareImage()
        }
    }

    private var locationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("地点").font(.headline)
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(DesignSystem.secondaryInk)
                TextField("未填写，可补充", text: $locationDraft)
                    .focused($locationFocused)
                    .submitLabel(.done)
                    .onSubmit(saveLocation)
                if locationDraft != (session.locationName ?? "") {
                    Button("保存", action: saveLocation)
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func saveLocation() {
        drinkRepository.updateLocation(of: session, to: locationDraft)
        locationDraft = session.locationName ?? ""
        locationFocused = false
        renderShareImage()
    }

    /// 把 ShareCardView 渲染成图片用于系统分享面板。
    /// 注意：ImageRenderer 渲染的是一棵独立的 View 树，不会自动继承当前的 environmentObject，
    /// 必须显式把 HealthKitManager.shared 注入进去，否则 ShareCardView 里的
    /// @EnvironmentObject 在渲染时找不到依赖会直接崩溃。
    @MainActor
    private func renderShareImage() {
        let content = ShareCardView(session: session, includeHeartRateCurve: includeHeartRateCurve, showLocation: showLocationOnCard)
            .frame(width: ShareCardView.renderWidth)
            .background(DesignSystem.pagePlane)
            .environmentObject(HealthKitManager.shared)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
