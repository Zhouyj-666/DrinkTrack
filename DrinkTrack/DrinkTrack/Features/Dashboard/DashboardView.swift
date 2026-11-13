import SwiftUI
import CoreData

/// §5.3 实时状态仪表盘：饮酒记录列表、心率曲线、血氧展示、被动预警、会话开始/结束控制。
struct DashboardView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @Environment(\.managedObjectContext) private var context

    @State private var activeSession: DrinkSessionEntity?
    /// 最近 12 小时内结束的上一场，用于「上一场」小结卡片（查看详情 / 生成分享卡）。
    @State private var lastEndedSession: DrinkSessionEntity?
    @State private var showQuickLog = false
    @State private var activeAlertMessage: String?
    @State private var restingHeartRate: Double = 65
    /// 录入后自增，用来强制刷新依赖会话关系的派生数据（Core Data 关系变更不会自动发布）
    @State private var logRevision = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        SessionControlView(
                            drinkRepository: drinkRepository,
                            activeSession: $activeSession,
                            showQuickLog: $showQuickLog
                        )

                        if activeSession == nil, let last = lastEndedSession {
                            NavigationLink {
                                SessionDetailView(session: last)
                            } label: {
                                LastSessionCard(session: last)
                            }
                            .buttonStyle(.plain)
                        }

                        // 录入的记录现在第一时间可见（修复「记录不显示」）
                        if activeSession != nil {
                            SessionLogListView(session: activeSession)
                                .id(logRevision)
                        }

                        // 健康数据没连上时，把状态和自查方法摆在显眼处，
                        // 而不是让用户对着一张空图表猜为什么没数据
                        if !healthKitManager.connectionState.isUsable {
                            HealthConnectionStatusView(
                                state: healthKitManager.connectionState,
                                authorizationError: healthKitManager.authorizationError,
                                isRequesting: healthKitManager.isRequestingAuthorization,
                                onRequestAuthorization: {
                                    Task { await healthKitManager.requestAuthorization() }
                                },
                                onRefresh: {
                                    Task { await healthKitManager.refreshConnectionState() }
                                }
                            )
                        }

                        HeartRateChartView(
                            points: healthKitManager.recentHeartRatePoints,
                            drinkMarks: drinkMarkTimestamps,
                            watchConnected: healthKitManager.watchSeemsConnected
                        )

                        if !healthKitManager.recentSpO2Points.isEmpty || healthKitManager.latestSpO2 != nil {
                            SpO2View(points: healthKitManager.recentSpO2Points, current: healthKitManager.latestSpO2)
                        }
                    }
                    .padding()
                }

                if let message = activeAlertMessage {
                    AlertToastView(message: message) { activeAlertMessage = nil }
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("仪表盘")
            .task {
                activeSession = drinkRepository.fetchActiveSession()
                loadLastEndedSession()
                loadRestingHeartRate()
                await healthKitManager.resumeIfPossible()
            }
            .onChange(of: activeSession) { _, _ in
                loadLastEndedSession()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                evaluateAlerts()
            }
            .sheet(isPresented: $showQuickLog, onDismiss: {
                // 录入面板关掉后刷新列表和图表标记
                logRevision += 1
            }) {
                if let session = activeSession {
                    QuickLogSheet(session: session, drinkRepository: drinkRepository)
                }
            }
        }
    }

    private var drinkMarkTimestamps: [Date] {
        _ = logRevision // 建立依赖，录入后重新计算
        guard let session = activeSession, let logs = session.logs as? Set<DrinkLogEntity> else { return [] }
        return logs.compactMap(\.timestamp).sorted()
    }

    private func loadLastEndedSession() {
        guard let last = drinkRepository.fetchArchivedSessions(limit: 1).first,
              let endedAt = last.endedAt,
              Date().timeIntervalSince(endedAt) < 12 * 3600 else {
            lastEndedSession = nil
            return
        }
        lastEndedSession = last
    }

    private func loadRestingHeartRate() {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        if let profile = try? context.fetch(request).first {
            restingHeartRate = Double(profile.restingHeartRate)
        }
    }

    /// §6.2 被动预警判定：每分钟跑一次，而不是用持续运行的高频定时器。
    private func evaluateAlerts() {
        guard activeSession != nil else { return }

        let hrSamples = healthKitManager.recentHeartRatePoints.map { (timestamp: $0.timestamp, bpm: $0.value) }
        if let alert = AlertThresholdEngine.evaluateHeartRate(recentHeartRates: hrSamples, restingHeartRate: restingHeartRate) {
            activeAlertMessage = alert.message
            return
        }

        let spo2Samples = healthKitManager.recentSpO2Points.map { (timestamp: $0.timestamp, percent: $0.value) }
        if let alert = AlertThresholdEngine.evaluateSpO2(recentSpO2: spo2Samples) {
            activeAlertMessage = alert.message
        }
    }
}

/// 仪表盘上的「上一场」小结：结束会话后马上能看到本场摘要，点进去生成分享卡。
private struct LastSessionCard: View {
    @ObservedObject var session: DrinkSessionEntity

    private var logs: [DrinkLogEntity] {
        Array((session.logs as? Set<DrinkLogEntity>) ?? [])
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.title2)
                .foregroundStyle(DesignSystem.statusGood)
            VStack(alignment: .leading, spacing: 2) {
                Text("上一场已结束").font(.subheadline.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            Text("查看 / 分享")
                .font(.caption)
                .foregroundStyle(DesignSystem.heartRateLine)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var summary: String {
        let start = session.startedAt ?? Date()
        let end = session.endedAt ?? start
        let standard = logs.reduce(0.0) { $0 + $1.standardDrinks }
        var text = String(format: "%d 杯 · ≈%.1f 标准饮品 · ", logs.count, standard)
        text += UserPreferences.formatDuration(end.timeIntervalSince(start))
        if let place = session.locationName, !place.isEmpty {
            text += " · " + place
        }
        return text
    }
}
