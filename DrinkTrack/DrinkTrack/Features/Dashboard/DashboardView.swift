import SwiftUI
import CoreData

/// §5.3 实时状态仪表盘：饮酒记录列表、心率曲线、血氧展示、被动预警、会话开始/结束控制。
struct DashboardView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @Environment(\.managedObjectContext) private var context

    @State private var activeSession: DrinkSessionEntity?
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
                loadRestingHeartRate()
                await healthKitManager.resumeIfPossible()
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
