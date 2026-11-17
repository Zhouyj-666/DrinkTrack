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
    @State private var locationLatitude: Double? = nil
    @State private var locationLongitude: Double? = nil
    @State private var sessionNoteDraft = ""
    @State private var placeNoteDraft = ""
    @State private var renderedImage: Image?
    @State private var sessionAlerts: [AlertThresholdEngine.AlertResult] = []
    @StateObject private var locationProvider = LocationProvider()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SessionTimelineChart(session: session)

                SessionAlertsCard(alerts: sessionAlerts)

                locationEditor

                notesEditor

                SessionLogListView(session: session, sessionIsActive: session.status == "active")

                VStack(alignment: .leading, spacing: 8) {
                    Text("分享卡片").font(.headline)
                    Toggle("附加本场心率走势", isOn: $includeHeartRateCurve)
                    Toggle("在卡片上显示地点", isOn: $showLocationOnCard)
                        .disabled((session.locationName ?? "").isEmpty)
                    Text("卡片不会包含花费或坐标；心率只显示走势，不显示数值。地点默认关闭，打开后只显示地名。你写下的场次描述和地点描述会出现在卡片上，也不会带上坐标。")
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
                        preview: SharePreview("小酌场 饮酒打卡", image: renderedImage)
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
                    preview: SharePreview("小酌场 饮酒打卡", image: renderedImage ?? Image(systemName: "wineglass"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享")
            }
        }
        .onAppear {
            loadLocationDraft()
            loadNotesDraft()
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
            HStack {
                Text("地点").font(.headline)
                Spacer()
                if locationNeedsSave {
                    Button("保存", action: saveLocation)
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            }
            LocationInputField(
                locationName: $locationDraft,
                latitude: $locationLatitude,
                longitude: $locationLongitude,
                provider: locationProvider,
                knownCoordinate: { drinkRepository.knownCoordinate(forPlaceName: $0) },
                onResolved: saveLocation
            )
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var locationNeedsSave: Bool {
        let trimmed = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (session.locationName ?? "") { return true }
        let existing = LocationCoordinate.pair(from: session)
        let current = LocationCoordinate.validated(latitude: locationLatitude, longitude: locationLongitude)
        switch (existing, current) {
        case (nil, nil):
            return false
        case let (old?, new?):
            return old != new
        default:
            return true
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("描述").font(.headline)
                Spacer()
                if notesNeedSave {
                    Button("保存", action: saveNotes)
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("场次描述")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.mutedInk)
                TextField("这晚喝了什么，或一句短记", text: $sessionNoteDraft, axis: .vertical)
                    .lineLimit(2...4)
                Text("地点描述")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.mutedInk)
                    .padding(.top, 4)
                TextField("店名，或对这个地址的备注", text: $placeNoteDraft, axis: .vertical)
                    .lineLimit(2...4)
            }
            Text("这些描述只用来帮助你自己回忆。会出现在会话详情和饮酒打卡上，不会带上经纬度。")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var notesNeedSave: Bool {
        Self.trimmed(sessionNoteDraft) != Self.trimmed(session.value(forKey: "note") as? String)
            || Self.trimmed(placeNoteDraft) != Self.trimmed(session.value(forKey: "placeNote") as? String)
    }

    private func loadNotesDraft() {
        sessionNoteDraft = session.value(forKey: "note") as? String ?? ""
        placeNoteDraft = session.value(forKey: "placeNote") as? String ?? ""
    }

    private func saveNotes() {
        drinkRepository.updateSessionDescriptions(
            of: session,
            note: sessionNoteDraft,
            placeNote: placeNoteDraft
        )
        loadNotesDraft()
        renderShareImage()
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func loadLocationDraft() {
        locationDraft = session.locationName ?? ""
        if let pair = LocationCoordinate.pair(from: session)
            ?? drinkRepository.knownCoordinate(forPlaceName: locationDraft) {
            locationLatitude = pair.0
            locationLongitude = pair.1
        } else {
            locationLatitude = nil
            locationLongitude = nil
        }
    }

    private func saveLocation() {
        drinkRepository.updateLocation(
            of: session,
            to: locationDraft,
            latitude: locationLatitude,
            longitude: locationLongitude
        )
        loadLocationDraft()
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
